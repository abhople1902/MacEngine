//
//  MetricsCollector.swift
//  MonitoringService
//
//  All sampling for the whole system happens here, in a process that is not the
//  UI. The samplers themselves are the ones from Block A, moved into `Shared`
//  and otherwise untouched — the architecture changed, the measurement code did
//  not.
//

import OSLog
import Foundation

/// `NSXPCConnection` is documented as thread-safe but is not `Sendable`, so
/// handing one to an actor needs an explicit unchecked wrapper. Sending is
/// wrapped in an error handler because the app can vanish at any moment.
nonisolated struct ClientChannel: @unchecked Sendable {
    let connection: NSXPCConnection

    func send(_ payload: Data) {
        client()?.didProduceSnapshot(payload)
    }

    func sendScanUpdate(_ payload: Data) {
        client()?.didUpdateScan(payload)
    }

    private func client() -> MonitoringClientProtocol? {
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            Log.xpc.error("Push to client failed: \(error.localizedDescription, privacy: .public)")
        }
        return proxy as? MonitoringClientProtocol
    }
}

actor MetricsCollector {
    /// Process enumeration costs a `proc_pidinfo` call per process — roughly
    /// six hundred of them. System metrics are cheap enough to take on every
    /// tick, so the two run on separate cadences and the process list is
    /// reused in between.
    private static let processRefreshInterval: TimeInterval = 1.0
    private static let topProcessCount = 5

    private let cpuSampler = CPUSampler()
    private let memorySampler = MemorySampler()
    private let diskSampler = DiskSampler()
    private let processSampler = ProcessSampler()

    private let startedAt = Date()
    private var samplesTaken = 0
    private var isMonitoring = false
    private var sampleInterval: TimeInterval = 1.0

    private var cachedProcesses: [ProcessSample] = []
    private var processesSampledAt: Date?

    private var pushTask: Task<Void, Never>?
    private var channel: ClientChannel?

    func attach(_ channel: ClientChannel) {
        self.channel = channel
    }

    func info() -> ServiceInfo {
        ServiceInfo(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            startedAt: startedAt,
            samplesTaken: samplesTaken,
            isMonitoring: isMonitoring,
            sampleInterval: sampleInterval
        )
    }

    func start(interval: TimeInterval) {
        sampleInterval = Swift.max(interval, 0.1)
        guard !isMonitoring else { return }
        isMonitoring = true

        // Prime both delta-based samplers so the first published sample spans a
        // real interval rather than all of uptime.
        cpuSampler.reset()
        processSampler.reset()
        _ = cpuSampler.sample()

        Log.metrics.info("Service sampling started at \(self.sampleInterval, format: .fixed(precision: 2))s")
        MonitoringEventBus.post(.monitoringStarted, detail: "service pid \(ProcessInfo.processInfo.processIdentifier)")

        pushTask = Task { [weak self] in
            await self?.runPushLoop()
        }
    }

    /// Exposed for the workspace scan, which wants the toolchain's live cost
    /// alongside its disk cost and should not own a second process sampler.
    func toolchainFootprint() -> ToolchainFootprint {
        processSampler.toolchainFootprint()
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        pushTask?.cancel()
        pushTask = nil
        cpuSampler.reset()

        Log.metrics.info("Service sampling stopped after \(self.samplesTaken) samples")
        MonitoringEventBus.post(.monitoringStopped, detail: "\(samplesTaken) samples")
    }

    /// One reading taken now, whether or not the push loop is running, so a
    /// client that only ever polls still gets real data.
    func snapshot(now: Date = Date()) -> MetricSnapshot {
        samplesTaken += 1

        let collectStarted = Date()
        let cpu = cpuSampler.sample()
        let memory = memorySampler.sample()
        let disk = diskSampler.sample(now: now)
        let processes = topProcesses(now: now)

        return MetricSnapshot(
            timestamp: now,
            cpu: cpu,
            memory: memory,
            disk: disk,
            topProcesses: processes,
            timing: PipelineTiming(
                collectStarted: collectStarted,
                collectEnded: Date(),
                // Overwritten the instant before encoding actually starts.
                encodeStarted: Date()
            )
        )
    }

    private func topProcesses(now: Date) -> [ProcessSample] {
        if let processesSampledAt,
           now.timeIntervalSince(processesSampledAt) < Self.processRefreshInterval {
            return cachedProcesses
        }

        cachedProcesses = processSampler.sample(limit: Self.topProcessCount, now: now)
        processesSampledAt = now
        return cachedProcesses
    }

    private func runPushLoop() async {
        let encoder = JSONEncoder()

        while !Task.isCancelled, isMonitoring {
            if let channel {
                do {
                    var snapshot = snapshot()
                    snapshot.timing?.encodeStarted = Date()
                    channel.send(try encoder.encode(snapshot))
                } catch {
                    Log.xpc.error("Snapshot encode failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            do {
                try await Task.sleep(for: .seconds(sampleInterval))
            } catch {
                return // cancelled while sleeping
            }
        }
    }
}
