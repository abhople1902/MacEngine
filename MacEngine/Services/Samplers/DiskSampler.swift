//
//  DiskSampler.swift
//  MacEngine
//
//  Capacity of the boot volume. Cheap, but not free — the value is cached and
//  refreshed on a slower cadence than CPU and memory.
//

import OSLog
import Foundation

nonisolated final class DiskSampler {
    private static let refreshInterval: TimeInterval = 10

    private let volumeURL: URL
    private var cached: DiskMetrics?
    private var lastRead: Date?

    init(volumeURL: URL = URL(fileURLWithPath: "/")) {
        self.volumeURL = volumeURL
    }

    func sample(now: Date = Date()) -> DiskMetrics {
        if let cached, let lastRead, now.timeIntervalSince(lastRead) < Self.refreshInterval {
            return cached
        }

        let metrics = read()
        cached = metrics
        lastRead = now
        return metrics
    }

    private func read() -> DiskMetrics {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]

        do {
            let values = try volumeURL.resourceValues(forKeys: keys)
            let total = UInt64(max(values.volumeTotalCapacity ?? 0, 0))
            let available = UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0))
            return DiskMetrics(
                volumeName: values.volumeName ?? volumeURL.lastPathComponent,
                totalBytes: total,
                availableBytes: available
            )
        } catch {
            Log.metrics.error("Volume capacity read failed: \(error.localizedDescription, privacy: .public)")
            return cached ?? .zero
        }
    }
}
