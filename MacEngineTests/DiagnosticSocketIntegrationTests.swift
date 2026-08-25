import XCTest
@testable import MacEngine

final class DiagnosticSocketIntegrationTests: XCTestCase {
    private let interval: TimeInterval = 0.5
    private var path: String { MonitoringIdentifiers.diagnosticSocketPath }

    private func waitForSocket(timeout: TimeInterval = 15) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let reply = try? request("help"), !reply.isEmpty { return }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTFail("Timed out waiting for the diagnostic socket at \(path)")
    }

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
