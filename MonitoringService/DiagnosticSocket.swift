//
//  DiagnosticSocket.swift
//  MonitoringService
//
//  A second front door onto the same service.
//
//  XPC is the right transport for the app: typed, authenticated, and able to
//  push. It is the wrong transport for everything else, because reaching it
//  means being a Mach client with a matching interface. A Unix domain socket
//  costs almost nothing and is reachable from a shell script, a CLI, or `nc`.
//  Same data, second door — which is the whole point of the exercise.
//
//  Threading is the part worth reading. The accept loop is driven by a
//  DispatchSource on a non-blocking listening descriptor, so no thread ever
//  sits in `accept(2)`. Each accepted connection is read on a Dispatch queue —
//  a thread that is *allowed* to block — and only the part that needs the
//  actor hops onto the cooperative pool. Reading a socket from inside a Task
//  would occupy one of the pool's handful of threads for as long as the peer
//  felt like taking, which is exactly the starvation `DiskWalker` yields to
//  avoid.
//

import OSLog
import Foundation

/// Owns the listening descriptor for the lifetime of the process.
///
/// `@unchecked Sendable` because the descriptor and the DispatchSource are
/// mutated only on `queue`, which is serial — the compiler cannot see that
/// invariant, so it is asserted here and kept by convention below.
final class DiagnosticSocket: @unchecked Sendable {
    /// Requests are a single short verb; anything larger is a client bug or a
    /// probe, and is dropped rather than buffered.
    private static let maximumRequestBytes = 256

    /// A client that connects and then says nothing must not hold a queue
    /// thread indefinitely.
    private static let ioTimeout = timeval(tv_sec: 3, tv_usec: 0)

    private let path: String
    private let collector: MetricsCollector

    private let queue = DispatchQueue(label: "com.AyushBhople.MacEngine.diagnostic.accept")
    private let connections = DispatchQueue(
        label: "com.AyushBhople.MacEngine.diagnostic.connection",
        attributes: .concurrent
    )

    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?

    init(path: String = MonitoringIdentifiers.diagnosticSocketPath, collector: MetricsCollector) {
        self.path = path
        self.collector = collector
    }

    // MARK: - Lifecycle

    /// Binds and starts accepting. Failures are logged and swallowed: a
    /// diagnostic channel that cannot open must never stop the service from
    /// doing its actual job.
    func start() {
        queue.async { [self] in
            guard descriptor < 0 else { return }

            // sun_path is a fixed 104-byte field. A path that does not fit
            // would be silently truncated and bind somewhere unintended.
            guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
                Log.xpc.error("Diagnostic socket path is too long for sockaddr_un")
                return
            }

            // A previous run that died without unlinking leaves a stale node
            // behind, and bind(2) refuses to reuse it. But "the node exists"
            // and "someone is listening on it" are different facts, and only
            // the first justifies removing it — unlinking unconditionally
            // would let a second instance silently steal a live socket from
            // the first. So: probe, and stand down if anyone answers.
            if FileManager.default.fileExists(atPath: path) {
                guard !Self.someoneIsListening(at: path) else {
                    Log.xpc.info("Diagnostic socket already owned by another instance; not binding")
                    return
                }
                unlink(path)
            }

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                Log.xpc.error("Diagnostic socket() failed: errno \(errno)")
                return
            }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutablePointer(to: &address.sun_path) { field in
                field.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: field.pointee)) { bytes in
                    _ = strcpy(bytes, path)
                }
            }
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    bind(fd, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0 else {
                Log.xpc.error("Diagnostic socket bind failed: errno \(errno)")
                close(fd)
                return
            }

            guard listen(fd, 8) == 0 else {
                Log.xpc.error("Diagnostic socket listen failed: errno \(errno)")
                close(fd)
                unlink(path)
                return
            }

            // Only this user talks to it. The socket exposes machine state, and
            // /tmp is world-writable.
            chmod(path, 0o600)

            // Non-blocking, because the DispatchSource — not a parked thread —
            // is what waits for connections.
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)

            descriptor = fd

            let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            readSource.setEventHandler { [weak self] in self?.acceptPending() }
            readSource.setCancelHandler { close(fd) }
            readSource.resume()
            source = readSource

            Log.xpc.info("Diagnostic socket listening on \(self.path, privacy: .public)")
            Task { [collector, path] in await collector.setDiagnosticSocket(path) }
        }
    }

    func stop() {
        queue.async { [self] in
            source?.cancel()
            source = nil
            descriptor = -1
            unlink(path)
        }
    }

    // MARK: - Accept

    /// Drains everything the backlog holds. The source fires once per
    /// readiness edge, so accepting a single connection per firing would leave
    /// clients queued behind a socket that never becomes "more" readable.
    private func acceptPending() {
        while true {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { return }
            connections.async { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        var timeout = Self.ioTimeout
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard let line = readLine(client) else {
            close(client)
            return
        }

        let request = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // The async half. Everything above this point ran on a queue that may
        // block; everything below needs the actor and must not.
        Task { [collector] in
            let reply: String

            switch DiagnosticVerb(rawValue: request) {
            case .status:
                reply = DiagnosticReport.status(info: await collector.info(), snapshot: await collector.latest())
            case .snapshot:
                if let snapshot = await collector.latest(),
                   let data = try? JSONEncoder().encode(snapshot),
                   let json = String(data: data, encoding: .utf8) {
                    reply = json
                } else {
                    reply = "no snapshot yet"
                }
            case .help:
                reply = DiagnosticReport.help()
            case nil:
                reply = request.isEmpty ? DiagnosticReport.help() : DiagnosticReport.unknown(request)
            }

            send(reply + "\n", to: client)
            close(client)
        }
    }

    /// True if a connect(2) to `path` succeeds, meaning a live process owns
    /// the socket. A refusal means the node is stale and safe to replace.
    private static func someoneIsListening(at path: String) -> Bool {
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { return false }
        defer { close(probe) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutablePointer(to: &address.sun_path) { field in
            field.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: field.pointee)) { bytes in
                _ = strcpy(bytes, path)
            }
        }

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                connect(probe, generic, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
    }

    // MARK: - Bytes

    /// Reads up to the first newline. Returns nil on timeout, error, or a peer
    /// that hangs up without saying anything.
    private func readLine(_ client: Int32) -> String? {
        var collected = [UInt8]()
        var byte: UInt8 = 0

        while collected.count < Self.maximumRequestBytes {
            let got = read(client, &byte, 1)
            guard got == 1 else { return collected.isEmpty ? nil : String(decoding: collected, as: UTF8.self) }
            if byte == UInt8(ascii: "\n") { break }
            collected.append(byte)
        }

        return String(decoding: collected, as: UTF8.self)
    }

    /// `write(2)` is free to accept fewer bytes than it was handed, so a single
    /// call is not enough even for a reply this small.
    private func send(_ text: String, to client: Int32) {
        var remaining = Array(text.utf8)
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { buffer in
                Darwin.write(client, buffer.baseAddress, buffer.count)
            }
            guard written > 0 else { return }
            remaining.removeFirst(written)
        }
    }
}
