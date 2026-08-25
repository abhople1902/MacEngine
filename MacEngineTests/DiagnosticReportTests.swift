//
//  DiagnosticReportTests.swift
//  MacEngineTests
//
//  The socket's wording, tested without a socket. This is the reason the text
//  lives in `Shared` as a pure function rather than inside the listener.
//

import XCTest
@testable import MacEngine

final class DiagnosticReportTests: XCTestCase {
    private func info(
        monitoring: Bool = true,
        samples: Int = 42,
        startedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) -> ServiceInfo {
        ServiceInfo(
            processIdentifier: 4321,
            startedAt: startedAt,
            samplesTaken: samples,
            isMonitoring: monitoring,
            sampleInterval: 1.0,
            diagnosticSocketPath: "/tmp/macengine-diagnostic.sock"
        )
    }

    private func snapshot(swapUsed: UInt64 = 0) -> MetricSnapshot {
        MetricSnapshot(
            timestamp: Date(timeIntervalSinceReferenceDate: 0),
            cpu: CPUMetrics(
                userFraction: 0.20,
                systemFraction: 0.05,
                niceFraction: 0,
                idleFraction: 0.75,
                coreCount: 8
            ),
            memory: MemoryMetrics(
                totalBytes: 8_000_000_000,
                appBytes: 3_000_000_000,
                wiredBytes: 1_000_000_000,
                compressedBytes: 0,
                freeBytes: 4_000_000_000,
                swap: SwapUsage(totalBytes: 2_000_000_000, usedBytes: swapUsed)
            ),
            disk: DiskMetrics(
                volumeName: "Macintosh HD",
                totalBytes: 1_000_000_000,
                availableBytes: 250_000_000
            ),
            topProcesses: []
        )
    }

    func testStatusSaysSoWhenNothingHasSampledYet() {
        let text = DiagnosticReport.status(info: info(monitoring: false, samples: 0), snapshot: nil)
        XCTAssertTrue(text.contains("no snapshot yet"))
    }

    func testStatusReportsTheServicePid() {
        let text = DiagnosticReport.status(info: info(), snapshot: snapshot())
        XCTAssertTrue(text.contains("4321"))
    }

    /// A machine with no swap in use should not get a swap line at all —
    /// "0 B of 0 B" reads like a fault rather than a healthy machine.
    func testSwapLineIsOmittedWhenSwapIsUnused() {
        let text = DiagnosticReport.status(info: info(), snapshot: snapshot(swapUsed: 0))
        XCTAssertFalse(text.contains("swap"))
    }

    func testSwapLineAppearsOnceSwapIsInUse() {
        let text = DiagnosticReport.status(info: info(), snapshot: snapshot(swapUsed: 500_000_000))
        XCTAssertTrue(text.contains("swap"))
    }

    func testUptimeIsClockFormatted() {
        XCTAssertEqual(DiagnosticReport.duration(3661), "01:01:01")
    }

    /// Decimal units, matching the rest of the app rather than the binary
    /// units a naive shift would produce.
    func testBytesUseDecimalUnits() {
        XCTAssertEqual(DiagnosticReport.bytes(2_500_000_000), "2.50 GB")
    }

    func testSmallByteCountsStayInBytes() {
        XCTAssertEqual(DiagnosticReport.bytes(512), "512 B")
    }

    func testEveryVerbIsDocumentedInHelp() {
        let help = DiagnosticReport.help()
        XCTAssertTrue(DiagnosticVerb.allCases.allSatisfy { help.contains($0.rawValue) })
    }

    /// `ServiceInfo` crosses XPC as JSON, so the socket path added for the
    /// topology panel has to survive the round trip like everything else.
    func testServiceInfoCarriesTheSocketPathAcrossTheWire() throws {
        let encoded = try JSONEncoder().encode(info())
        let decoded = try JSONDecoder().decode(ServiceInfo.self, from: encoded)
        XCTAssertEqual(decoded.diagnosticSocketPath, "/tmp/macengine-diagnostic.sock")
    }

    /// Absent is a real state: binding is allowed to fail, and a second app
    /// instance deliberately does not steal a socket the first one owns.
    func testServiceInfoDecodesWhenNoSocketWasBound() throws {
        var withoutSocket = info()
        withoutSocket.diagnosticSocketPath = nil
        let decoded = try JSONDecoder().decode(
            ServiceInfo.self,
            from: try JSONEncoder().encode(withoutSocket)
        )
        XCTAssertNil(decoded.diagnosticSocketPath)
    }

    func testUnknownVerbIsEchoedBackWithTheVerbList() {
        let text = DiagnosticReport.unknown("wat")
        XCTAssertTrue(text.contains("wat") && text.contains("status"))
    }
}
