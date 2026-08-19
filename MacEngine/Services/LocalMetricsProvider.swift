//
//  LocalMetricsProvider.swift
//  MacEngine
//
//  Block A stand-in: samples the machine inside the app's own process.
//
//  This exists so the dashboard is real from day one, not so the app should
//  ship this way — a crash in a sampler here takes the whole UI with it, which
//  is exactly the problem the XPC service in Block B solves. The samplers
//  themselves move across unchanged; only the provider is replaced.
//

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
        // Prime the CPU counters so the first reported sample spans a real
        // interval rather than all of uptime.
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
