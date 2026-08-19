//
//  DashboardViewModelTests.swift
//  MacEngineTests
//
//  Drives the view model against a stub provider so the sampling loop, the
//  history window and the failure handling can be tested without the machine.
//

import XCTest
@testable import MacEngine

@MainActor
final class DashboardViewModelTests: XCTestCase {

    func testStartStreamsSnapshotsFromTheProvider() async throws {
        let model = DashboardViewModel(provider: StubMetricsProvider())
        model.sampleInterval = 0.01
        model.start()

        try await waitUntil("a snapshot arrives") { model.latest != nil }

        XCTAssertEqual(model.connectionState, .streaming)
        XCTAssertGreaterThan(model.samplesTaken, 0)
        model.stop()
    }

    func testStopReturnsTheModelToIdle() async throws {
        let model = DashboardViewModel(provider: StubMetricsProvider())
        model.sampleInterval = 0.01
        model.start()
        try await waitUntil("a snapshot arrives") { model.latest != nil }

        model.stop()

        XCTAssertEqual(model.connectionState, .idle)
    }

    func testHistoryKeepsSnapshotsOldestFirst() async throws {
        let model = DashboardViewModel(provider: StubMetricsProvider())
        model.sampleInterval = 0.01
        model.start()

        try await waitUntil("three snapshots arrive") { model.recentSnapshots.count >= 3 }
        model.stop()

        let timestamps = model.recentSnapshots.map(\.timestamp)
        XCTAssertEqual(timestamps, timestamps.sorted())
    }

    func testClearHistoryEmptiesTheWindow() async throws {
        let model = DashboardViewModel(provider: StubMetricsProvider())
        model.sampleInterval = 0.01
        model.start()
        try await waitUntil("a snapshot arrives") { model.latest != nil }
        model.stop()

        model.clearHistory()

        XCTAssertTrue(model.recentSnapshots.isEmpty)
        XCTAssertNil(model.latest)
        XCTAssertEqual(model.samplesTaken, 0)
    }

    func testAnInProcessFailureIsTerminalRatherThanRecoverable() async throws {
        let model = DashboardViewModel(provider: StubMetricsProvider(source: .local, startsFailing: true))
        model.sampleInterval = 0.01
        model.start()

        try await waitUntil("the failure is observed") {
            if case .failed = model.connectionState { return true }
            return false
        }
        model.stop()
    }

    func testAnOutOfProcessFailurePutsTheModelIntoRecovery() async throws {
        let model = DashboardViewModel(provider: StubMetricsProvider(source: .xpcService, startsFailing: true))
        model.sampleInterval = 0.01
        model.start()

        try await waitUntil("recovery starts") {
            if case .recovering = model.connectionState { return true }
            return false
        }
        model.stop()

        XCTAssertTrue(model.events.contains { $0.event == .serviceUnavailable })
    }

    func testRecoveryIsRecordedWhenSnapshotsResume() async throws {
        let provider = StubMetricsProvider(source: .xpcService, startsFailing: true)
        let model = DashboardViewModel(provider: provider)
        model.sampleInterval = 0.01
        model.start()

        try await waitUntil("recovery starts") {
            if case .recovering = model.connectionState { return true }
            return false
        }
        await provider.setShouldFail(false)

        try await waitUntil("streaming resumes") { model.connectionState == .streaming }
        model.stop()

        XCTAssertTrue(model.events.contains { $0.event == .serviceRecovered })
    }

    // MARK: - Helpers

    /// Polls rather than sleeping a fixed duration, so a fast machine finishes
    /// fast and a slow one still passes.
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting until \(description)")
    }
}

/// Emits canned snapshots and can be told to fail on demand.
private actor StubMetricsProvider: MetricsProviding {
    nonisolated let source: MetricsSource

    private var shouldFail: Bool

    init(source: MetricsSource = .local, startsFailing: Bool = false) {
        self.source = source
        self.shouldFail = startsFailing
    }

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func start(interval: TimeInterval) async {}

    func stop() async {}

    func snapshot() async throws -> MetricSnapshot {
        guard !shouldFail else {
            throw MetricsProviderError.unavailable("Stubbed failure")
        }
        return MetricSnapshot(
            timestamp: Date(),
            cpu: CPUMetrics(
                userFraction: 0.2,
                systemFraction: 0.1,
                niceFraction: 0,
                idleFraction: 0.7,
                coreCount: 8
            ),
            memory: MemoryMetrics(
                totalBytes: 16_000_000_000,
                appBytes: 6_000_000_000,
                wiredBytes: 2_000_000_000,
                compressedBytes: 400_000_000,
                freeBytes: 7_600_000_000
            ),
            disk: DiskMetrics(
                volumeName: "Stub HD",
                totalBytes: 500_000_000_000,
                availableBytes: 250_000_000_000
            )
        )
    }
}
