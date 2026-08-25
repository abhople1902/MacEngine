import OSLog
import Foundation

actor LocalMetricsProvider: MetricsProviding {
    nonisolated let source = MetricsSource.local

    private let cpuSampler = CPUSampler()
    private let memorySampler = MemorySampler()
    private let diskSampler = DiskSampler()

    private var isRunning = false
    private(set) var samplesTaken = 0
    private(set) var startedAt: Date?

    func start(interval: TimeInterval) async {
        guard !isRunning else { return }
        isRunning = true
        startedAt = Date()
        cpuSampler.reset()
        _ = cpuSampler.sample()
        Log.metrics.info("Local sampling started at \(interval, format: .fixed(precision: 2))s")
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false
        cpuSampler.reset()
        Log.metrics.info("Local sampling stopped after \(self.samplesTaken) samples")
    }

    func snapshot() async throws -> MetricSnapshot {
        guard isRunning else {
            throw MetricsProviderError.unavailable("Sampling is stopped")
        }
        samplesTaken += 1
        return MetricSnapshot(
            cpu: cpuSampler.sample(),
            memory: memorySampler.sample(),
            disk: diskSampler.sample(),
            topProcesses: []
        )
    }
}
