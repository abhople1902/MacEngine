//
//  DiagnosticSocketIntegrationTests.swift
//  MacEngineTests
//
//  The socket half of the second front door, against the real service.
//
//  These deliberately speak the protocol with raw syscalls rather than reusing
//  the CLI's client: the claim being tested is that *anything* which can open
//  an AF_UNIX socket can query the service, and a test that shared code with
//  the client could not detect a protocol change that broke every other caller.
//

import XCTest
@testable import MacEngine

final class DiagnosticSocketIntegrationTests: XCTestCase {
    private let interval: TimeInterval = 0.5
    private var path: String { MonitoringIdentifiers.diagnosticSocketPath }

    /// The service binds the socket shortly after launch, and launch is
    /// triggered by the first XPC message rather than by connecting.
    private func waitForSocket(timeout: TimeInterval = 15) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let reply = try? request("help"), !reply.isEmpty { return }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTFail("Timed out waiting for the diagnostic socket at \(path)")
    }

    /// One request, one reply, read to EOF.
    private func request(_ verb: String) throws -> String {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.ECONNREFUSED) }
        defer { close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutablePointer(to: &address.sun_path) { field in
            field.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: field.pointee)) { bytes in
                _ = strcpy(bytes, path)
            }
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                connect(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let line = Array((verb + "\n").utf8)
        _ = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }

        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let got = read(descriptor, &chunk, chunk.count)
            guard got > 0 else { break }
            reply.append(contentsOf: chunk[0..<got])
        }
        return String(decoding: reply, as: UTF8.self)
    }

    func testTheSocketAnswersARequestThatNeverTouchedXPC() async throws {
        let provider = XPCMetricsProvider()
        await provider.start(interval: interval)
        defer { Task { await provider.stop() } }

        try await waitForSocket()

        let status = try request("status")
        XCTAssertTrue(status.contains("service pid"), "Got: \(status)")
    }

    /// Asserts the socket is answering from *some* other process, not that it
    /// is answering from this test host's own service.
    ///
    /// The stronger claim — socket and XPC being two doors onto one process —
    /// is true when the app runs normally but cannot be asserted here. XCTest
    /// distributes classes across several test-host processes, each of which
    /// gets its own embedded service, and the socket path is a single
    /// well-known name that exactly one of them can own. Whichever bound first
    /// keeps it, so the pid answering may legitimately belong to a sibling
    /// host. Testing identity would be testing the scheduler.
    func testTheSocketReportsAnOutOfProcessService() async throws {
        let provider = XPCMetricsProvider()
        await provider.start(interval: interval)
        defer { Task { await provider.stop() } }

        try await waitForSocket()

        let status = try request("status")
        let reported = status
            .split(separator: "\n")
            .first { $0.hasPrefix("service pid") }
            .flatMap { Int32($0.filter(\.isNumber)) }

        let pid = try XCTUnwrap(reported, "No pid line in: \(status)")
        XCTAssertNotEqual(
            pid,
            ProcessInfo.processInfo.processIdentifier,
            "The socket must be served by the monitoring service, not the caller"
        )
    }

    func testSnapshotVerbReturnsDecodableJSON() async throws {
        let provider = XPCMetricsProvider()
        await provider.start(interval: interval)
        defer { Task { await provider.stop() } }

        try await waitForSocket()

        // The push loop has to have produced at least one reading first: the
        // socket reports state, it does not sample on demand.
        var payload = ""
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            payload = try request("snapshot")
            if payload.hasPrefix("{") { break }
            try await Task.sleep(for: .milliseconds(200))
        }

        let data = try XCTUnwrap(payload.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(MetricSnapshot.self, from: data)
        XCTAssertGreaterThan(snapshot.memory.totalBytes, 0)
    }

    func testUnknownVerbsAreRejectedRatherThanIgnored() async throws {
        let provider = XPCMetricsProvider()
        await provider.start(interval: interval)
        defer { Task { await provider.stop() } }

        try await waitForSocket()

        let reply = try request("definitely-not-a-verb")
        XCTAssertTrue(reply.contains("unknown verb"), "Got: \(reply)")
    }

}
