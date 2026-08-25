import OSLog
import Foundation

final class DiagnosticSocket: @unchecked Sendable {
    private static let maximumRequestBytes = 256

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

    func start() {
        queue.async { [self] in
            guard descriptor < 0 else { return }

            guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
                Log.xpc.error("Diagnostic socket path is too long for sockaddr_un")
                return
            }

            if FileManager.default.fileExists(atPath: path) {
            // Probe before unlinking, or a second instance silently steals a
            // live socket instead of replacing a stale node.
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

            chmod(path, 0o600)

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
