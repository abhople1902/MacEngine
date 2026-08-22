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

    /// Exercises the whole scan path — request out, updates back over the
    /// reverse channel — without measuring ten gigabytes in a unit test run.
    /// The scan is cancelled as soon as it reports that it started.
    func testWorkspaceScanReportsProgressAndHonoursCancellation() async throws {
        let provider = XPCMetricsProvider()
        await provider.start(interval: interval)
        defer { Task { await provider.stop() } }

        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "MacEngine.xcodeproj", directoryHint: .isDirectory)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: project.path),
            "Source tree not present in this run"
        )

        let updates = await provider.scanUpdates()
        let started = expectation(description: "scan started")
        let cancelled = expectation(description: "scan cancelled")

        let consumer = Task {
            for await update in updates {
                switch update {
                case .started: started.fulfill()
                case .cancelled: cancelled.fulfill()
                case .failed(let reason): XCTFail("Scan failed: \(reason)")
                default: break
                }
            }
        }
        defer { consumer.cancel() }

        try await provider.startScan(path: project.path)
        await fulfillment(of: [started], timeout: 15)

        await provider.cancelScan()
        await fulfillment(of: [cancelled], timeout: 15)
    }

    /// The map has to come from the service's own walk. If this ever returned
    /// the app's pid it would mean the app had found a way to read another
    /// task's regions, which is exactly what the design says it cannot do.
    func testTheServiceMapsItsOwnAddressSpaceRatherThanTheApps() async throws {
        let provider = XPCMetricsProvider()
        await provider.start(interval: interval)
        defer { Task { await provider.stop() } }

        let map = try await provider.addressSpaceMap()

        XCTAssertNotEqual(map.processIdentifier, ProcessInfo.processInfo.processIdentifier)
        XCTAssertGreaterThan(map.regionCount, 0)
        XCTAssertGreaterThan(map.virtualBytes, map.residentBytes)
        XCTAssertFalse(map.wasTruncated, "A healthy process should not hit the region cap")
    }

    /// Each leg is stamped by whichever process performed it, so a populated
    /// decode stamp is proof the snapshot really came from somewhere else.
    func testSnapshotsCarryTimingStampedOnBothSidesOfTheBoundary() async throws {
        let provider = XPCMetricsProvider()
        await provider.start(interval: interval)
        defer { Task { await provider.stop() } }

        var timing: PipelineTiming?
        try await waitUntil("a snapshot carrying decode stamps") {
            timing = (try? await provider.snapshot())?.timing
            return timing?.decodeEnded != nil
        }

        let stamped = try XCTUnwrap(timing)
        // `presented` belongs to the view model, so the provider sees three.
        XCTAssertEqual(stamped.stages.map(\.name), ["collect", "encode + transit", "decode"])
        XCTAssertTrue(stamped.stages.allSatisfy { $0.seconds >= 0 })
        XCTAssertGreaterThan(stamped.collectEnded.timeIntervalSince(stamped.collectStarted), 0)
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
