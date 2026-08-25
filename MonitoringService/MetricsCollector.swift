import OSLog
import Foundation

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

    private var latestSnapshot: MetricSnapshot?

    private var diagnosticSocketPath: String?

    func setDiagnosticSocket(_ path: String?) {
        diagnosticSocketPath = path
    }

    private var pushTask: Task<Void, Never>?
    private var channel: ClientChannel?

    func attach(_ channel: ClientChannel) {
        self.channel = channel
    }

    func latest() -> MetricSnapshot? { latestSnapshot }

    func info() -> ServiceInfo {
        ServiceInfo(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            startedAt: startedAt,
            samplesTaken: samplesTaken,
            isMonitoring: isMonitoring,
            sampleInterval: sampleInterval,
            diagnosticSocketPath: diagnosticSocketPath
        )
    }

    func start(interval: TimeInterval) {
        sampleInterval = Swift.max(interval, 0.1)
        guard !isMonitoring else { return }
        isMonitoring = true

        cpuSampler.reset()
        processSampler.reset()
        _ = cpuSampler.sample()

        Log.metrics.info("Service sampling started at \(self.sampleInterval, format: .fixed(precision: 2))s")
        MonitoringEventBus.post(.monitoringStarted, detail: "service pid \(ProcessInfo.processInfo.processIdentifier)")

        pushTask = Task { [weak self] in
            await self?.runPushLoop()
        }
    }

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

    func snapshot(now: Date = Date()) -> MetricSnapshot {
        samplesTaken += 1

        let collectStarted = Date()
        let cpu = cpuSampler.sample()
        let memory = memorySampler.sample()
        let disk = diskSampler.sample(now: now)
        let processes = topProcesses(now: now)

        let snapshot = MetricSnapshot(
            timestamp: now,
            cpu: cpu,
            memory: memory,
            disk: disk,
            topProcesses: processes,
            timing: PipelineTiming(
                collectStarted: collectStarted,
                collectEnded: Date(),
                encodeStarted: Date()
            )
        )

        latestSnapshot = snapshot
        return snapshot
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
                return
            }
        }
    }
}
