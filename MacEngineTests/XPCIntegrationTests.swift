//
//  XPCIntegrationTests.swift
//  MacEngineTests
//
//  These run against the real embedded service: the test host is MacEngine.app,
//  so `NSXPCConnection(serviceName:)` resolves the .xpc bundle inside it and a
//  second process really is launched. Nothing here is mocked, which is the
//  point — the mocked version of this test could not fail for the reasons that
//  matter.
//

import XCTest
@testable import MacEngine

final class XPCIntegrationTests: XCTestCase {
    private let interval: TimeInterval = 0.5

    /// Polls until `condition` holds. Used instead of a fixed sleep because
    /// process launch and XPC delivery have no guaranteed timing.
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 15,
        condition: () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Timed out waiting for \(description)")
    }

    func testSnapshotCrossesTheProcessBoundary() async throws {
        let provider = XPCMetricsProvider()
        await provider.start(interval: interval)
        defer { Task { await provider.stop() } }

        let snapshot = try await provider.snapshot()

        XCTAssertGreaterThan(snapshot.memory.totalBytes, 0)
        XCTAssertGreaterThan(snapshot.cpu.coreCount, 0)
        XCTAssertFalse(snapshot.disk.volumeName.isEmpty)
    }

    func testServiceRunsInADifferentProcessThanTheApp() async throws {
        let provider = XPCMetricsProvider()
        await provider.start(interval: interval)
        defer { Task { await provider.stop() } }

        let info = try await provider.serviceInfo()

        XCTAssertGreaterThan(info.processIdentifier, 0)
        XCTAssertNotEqual(
            info.processIdentifier,
            ProcessInfo.processInfo.processIdentifier,
            "Sampling must not be happening inside the app process"
        )
    }

    func testServicePushesSnapshotsWithoutBeingAsked() async throws {
        let provider = XPCMetricsProvider()
        await provider.start(interval: interval)
        defer { Task { await provider.stop() } }

        try await waitUntil("an unsolicited snapshot to arrive") {
            await provider.pushesReceived > 0
        }
    }

    func testProcessEnumerationHappensInTheService() async throws {
        let provider = XPCMetricsProvider()
        await provider.start(interval: interval)
        defer { Task { await provider.stop() } }

        // The first service-side sample has no CPU baseline, so wait for one
        // taken against a real interval.
        var processes: [ProcessSample] = []
        try await waitUntil("the service to report a process list") {
            processes = (try? await provider.snapshot())?.topProcesses ?? []
            return !processes.isEmpty
        }

        XCTAssertLessThanOrEqual(processes.count, 5)
        XCTAssertTrue(processes.allSatisfy { $0.pid > 0 && !$0.name.isEmpty })
    }

    func testServiceRecoversAfterACrash() async throws {
        let provider = XPCMetricsProvider()
        await provider.start(interval: interval)
        defer { Task { await provider.stop() } }

        _ = try await provider.snapshot()
        let before = try await provider.serviceInfo().processIdentifier

        await provider.simulateCrash()

        // The death must be surfaced, not silently papered over: the dashboard
        // shows "Reconnecting" precisely because snapshot() throws here.
        try await waitUntil("the provider to report the service as unavailable") {
            do {
                _ = try await provider.snapshot()
                return false
            } catch {
                return true
            }
        }

        // And then it must come back on its own, with no user action.
        try await waitUntil("snapshots to resume") {
            (try? await provider.snapshot()) != nil
        }

        let after = try await provider.serviceInfo().processIdentifier
        XCTAssertNotEqual(before, after, "A relaunched service must be a new process")
    }
}
