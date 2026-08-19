//
//  DashboardViewModel.swift
//  MacEngine
//
//  Owns the sampling loop, the rolling history and the connection state the
//  dashboard renders. It talks to `MetricsProviding` and never to a sampler
//  directly, so Block B can hand it an XPC-backed provider unchanged.
//

import OSLog
import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    /// Two minutes of history at the default one-second cadence.
    private static let historyCapacity = 120
    /// Consecutive samples above `highCPUThreshold` before an event is raised.
    private static let highCPUSampleCount = 3
    private static let highCPUThreshold = 0.85
    private static let eventLogCapacity = 50

    enum ConnectionState: Equatable {
        case idle
        case connecting
        case streaming
        case recovering(String)
        case failed(String)

        var isStreaming: Bool { self == .streaming }

        var label: String {
            switch self {
            case .idle: "Stopped"
            case .connecting: "Connecting"
            case .streaming: "Running"
            case .recovering: "Reconnecting"
            case .failed: "Unavailable"
            }
        }

        var detail: String? {
            switch self {
            case .recovering(let reason), .failed(let reason): reason
            case .idle, .connecting, .streaming: nil
            }
        }
    }

    private(set) var latest: MetricSnapshot?
    private(set) var connectionState: ConnectionState = .idle
    private(set) var events: [MonitoringEventRecord] = []
    private(set) var samplesTaken = 0

    var sampleInterval: TimeInterval = 1.0

    private var history = RingBuffer<MetricSnapshot>(capacity: DashboardViewModel.historyCapacity)
    private var provider: any MetricsProviding
    private var pollingTask: Task<Void, Never>?
    private let eventObservers = DistributedObserverBox()
    private var consecutiveHighCPUSamples = 0

    var source: MetricsSource { provider.source }

    /// Snapshots oldest to newest, for the history chart.
    var recentSnapshots: [MetricSnapshot] { history.elements }

    init(provider: any MetricsProviding = LocalMetricsProvider()) {
        self.provider = provider
        observeLifecycleEvents()
    }

    // MARK: - Sampling lifecycle

    func start() {
        guard pollingTask == nil else { return }
        connectionState = .connecting

        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.provider.start(interval: self.sampleInterval)
            await self.runSamplingLoop()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        consecutiveHighCPUSamples = 0
        connectionState = .idle

        Task { [provider] in
            await provider.stop()
        }
        record(.monitoringStopped)
    }

    func toggle() {
        pollingTask == nil ? start() : stop()
    }

    func clearHistory() {
        history.removeAll()
        latest = nil
        samplesTaken = 0
    }

    private func runSamplingLoop() async {
        record(.monitoringStarted, detail: provider.source.displayName)

        while !Task.isCancelled {
            do {
                let snapshot = try await provider.snapshot()
                guard !Task.isCancelled else { return }
                apply(snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                handle(error)
            }

            do {
                try await Task.sleep(for: .seconds(sampleInterval))
            } catch {
                return // cancelled while sleeping
            }
        }
    }

    private func apply(_ snapshot: MetricSnapshot) {
        if connectionState != .streaming {
            let wasDown = connectionState.detail != nil
            connectionState = .streaming
            if wasDown { record(.serviceRecovered) }
        }

        history.append(snapshot)
        latest = snapshot
        samplesTaken += 1
        checkCPUThreshold(snapshot.cpu)
    }

    private func handle(_ error: Error) {
        let reason = error.localizedDescription
        Log.metrics.error("Snapshot failed: \(reason, privacy: .public)")

        // A provider that isolates failure into another process is expected to
        // come back; an in-process failure will not fix itself.
        if provider.source.isolatesFailure {
            connectionState = .recovering(reason)
            record(.serviceUnavailable, detail: reason)
        } else {
            connectionState = .failed(reason)
        }
    }

    private func checkCPUThreshold(_ cpu: CPUMetrics) {
        guard cpu.busyFraction >= Self.highCPUThreshold else {
            consecutiveHighCPUSamples = 0
            return
        }

        consecutiveHighCPUSamples += 1
        guard consecutiveHighCPUSamples == Self.highCPUSampleCount else { return }
        record(
            .highCPUDetected,
            detail: cpu.busyFraction.formatted(.percent.precision(.fractionLength(0)))
        )
    }

    // MARK: - Lifecycle events

    /// In Block A every event is raised by this process. Block B moves the
    /// emitting side into the monitoring service and the background agent —
    /// this listener is already wired for them, and drops the notifications it
    /// posted itself so nothing is recorded twice.
    private func observeLifecycleEvents() {
        let center = DistributedNotificationCenter.default()
        let tokens = MonitoringEvent.allCases.map { event in
            center.addObserver(
                forName: event.notificationName,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let payload = MonitoringEventBus.payload(from: notification) else { return }
                MainActor.assumeIsolated {
                    self?.append(event, detail: payload.detail)
                }
            }
        }
        eventObservers.store(tokens)
    }

    /// Records an event this process raised, and broadcasts it so the CLI and
    /// the agent see it too.
    private func record(_ event: MonitoringEvent, detail: String? = nil) {
        append(event, detail: detail)
        MonitoringEventBus.post(event, detail: detail)
    }

    private func append(_ event: MonitoringEvent, detail: String?) {
        events.insert(MonitoringEventRecord(event: event, detail: detail), at: 0)
        if events.count > Self.eventLogCapacity {
            events.removeLast(events.count - Self.eventLogCapacity)
        }
        Log.events.info("\(event.displayName, privacy: .public) \(detail ?? "", privacy: .public)")
    }
}


/// Holds distributed-notification tokens and unregisters them when its owner
/// deallocates. `deinit` on a `@MainActor` type cannot touch isolated state, so
/// the tokens live out here instead.
private final class DistributedObserverBox: @unchecked Sendable {
    private var tokens: [NSObjectProtocol] = []

    func store(_ tokens: [NSObjectProtocol]) {
        self.tokens = tokens
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        for token in tokens {
            center.removeObserver(token)
        }
    }
}
