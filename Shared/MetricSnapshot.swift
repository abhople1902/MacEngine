//
//  MetricSnapshot.swift
//  Shared
//
//  The wire format between the monitoring engine and every consumer of it
//  (the app, the CLI, the background agent). Kept `Codable` so the XPC layer
//  can ship it as `Data` without any `NSSecureCoding` boilerplate.
//

import Foundation

/// One complete reading of the machine, taken at a single instant.
nonisolated struct MetricSnapshot: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let cpu: CPUMetrics
    let memory: MemoryMetrics
    let disk: DiskMetrics
    let topProcesses: [ProcessSample]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        cpu: CPUMetrics,
        memory: MemoryMetrics,
        disk: DiskMetrics,
        topProcesses: [ProcessSample] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.topProcesses = topProcesses
    }
}

nonisolated struct CPUMetrics: Codable, Sendable, Equatable {
    /// Fractions of total CPU time consumed since the previous sample, 0...1.
    let userFraction: Double
    let systemFraction: Double
    let niceFraction: Double
    let idleFraction: Double
    let coreCount: Int

    var busyFraction: Double {
        (userFraction + systemFraction + niceFraction).clampedToUnitInterval
    }

    static let zero = CPUMetrics(
        userFraction: 0,
        systemFraction: 0,
        niceFraction: 0,
        idleFraction: 1,
        coreCount: 1
    )
}

nonisolated struct MemoryMetrics: Codable, Sendable, Equatable {
    let totalBytes: UInt64
    /// Anonymous memory owned by running applications.
    let appBytes: UInt64
    /// Memory the kernel cannot page out.
    let wiredBytes: UInt64
    /// Footprint of the memory compressor.
    let compressedBytes: UInt64
    let freeBytes: UInt64

    var usedBytes: UInt64 { appBytes + wiredBytes + compressedBytes }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return (Double(usedBytes) / Double(totalBytes)).clampedToUnitInterval
    }

    var pressure: MemoryPressure {
        switch usedFraction {
        case ..<0.70: .normal
        case ..<0.90: .warning
        default: .critical
        }
    }

    static let zero = MemoryMetrics(
        totalBytes: 0,
        appBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        freeBytes: 0
    )
}

nonisolated enum MemoryPressure: String, Codable, Sendable, CaseIterable {
    case normal
    case warning
    case critical
}

nonisolated struct DiskMetrics: Codable, Sendable, Equatable {
    let volumeName: String
    let totalBytes: UInt64
    let availableBytes: UInt64

    var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return (Double(usedBytes) / Double(totalBytes)).clampedToUnitInterval
    }

    static let zero = DiskMetrics(volumeName: "—", totalBytes: 0, availableBytes: 0)
}

nonisolated extension Double {
    var clampedToUnitInterval: Double {
        guard isFinite else { return 0 }
        return Swift.min(Swift.max(self, 0), 1)
    }
}
