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

    /// Provenance: where this reading has been and how long each leg took.
    /// Filled in progressively as the snapshot crosses the process boundary.
    var timing: PipelineTiming?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        cpu: CPUMetrics,
        memory: MemoryMetrics,
        disk: DiskMetrics,
        topProcesses: [ProcessSample] = [],
        timing: PipelineTiming? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.topProcesses = topProcesses
        self.timing = timing
    }
}

/// What the snapshot cost on its way from the kernel to the screen.
///
/// The timestamps are plain wall-clock `Date`s taken in two different
/// processes, which is only sound because those processes are on the same host
/// and therefore reading the same clock. Across machines this would be
/// meaningless.
nonisolated struct PipelineTiming: Codable, Sendable, Equatable {
    // Stamped in the monitoring service.
    var collectStarted: Date
    var collectEnded: Date
    /// Stamped immediately before `JSONEncoder.encode` runs. There is no
    /// matching "encode ended" because that instant cannot be written into the
    /// thing being encoded — so encode and XPC transit are reported as one leg.
    var encodeStarted: Date

    // Stamped in the app.
    var decodeStarted: Date?
    var decodeEnded: Date?
    /// When the view model accepted it. The last instant the app can measure
    /// before SwiftUI's own render pass, which Instruments is the tool for.
    var presented: Date?

    var stages: [PipelineStage] {
        var stages = [
            PipelineStage(
                name: "collect",
                detail: "host_statistics64 · libproc · statfs",
                seconds: collectEnded.timeIntervalSince(collectStarted)
            )
        ]
        if let decodeStarted {
            stages.append(PipelineStage(
                name: "encode + transit",
                detail: "JSONEncoder, then across the XPC boundary",
                seconds: decodeStarted.timeIntervalSince(encodeStarted)
            ))
        }
        if let decodeStarted, let decodeEnded {
            stages.append(PipelineStage(
                name: "decode",
                detail: "JSONDecoder, in the app",
                seconds: decodeEnded.timeIntervalSince(decodeStarted)
            ))
        }
        if let decodeEnded, let presented {
            stages.append(PipelineStage(
                name: "hand off",
                detail: "onto the main actor and into the view model",
                seconds: presented.timeIntervalSince(decodeEnded)
            ))
        }
        return stages
    }

    var total: TimeInterval? {
        presented.map { $0.timeIntervalSince(collectStarted) }
    }
}

nonisolated struct PipelineStage: Sendable, Equatable, Identifiable {
    let name: String
    let detail: String
    let seconds: TimeInterval

    var id: String { name }

    /// Microseconds is the right unit here — every leg but collect is well
    /// under a millisecond, and rounding them all to "0 ms" hides the shape.
    var microseconds: Double { Swift.max(seconds, 0) * 1_000_000 }
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

    // Engineer Mode reads the full composition rather than the three-bucket
    // summary above. These default to zero so the summary can still be built
    // by hand in tests without naming every kernel counter.
    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let speculativeBytes: UInt64
    /// File-backed pages resident in active and inactive — "Cached Files".
    let fileBackedBytes: UInt64
    let swap: SwapUsage

    /// The kernel's own pressure level, read from
    /// `kern.memorystatus_vm_pressure_level`. This is *not* utilisation: a Mac
    /// can sit at 90% used and still report `.normal`, because the compressor
    /// is keeping up. `utilisationBand` is the other question.
    let pressure: MemoryPressure

    init(
        totalBytes: UInt64,
        appBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        freeBytes: UInt64,
        activeBytes: UInt64 = 0,
        inactiveBytes: UInt64 = 0,
        speculativeBytes: UInt64 = 0,
        fileBackedBytes: UInt64 = 0,
        swap: SwapUsage = .zero,
        pressure: MemoryPressure = .normal
    ) {
        self.totalBytes = totalBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.freeBytes = freeBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.speculativeBytes = speculativeBytes
        self.fileBackedBytes = fileBackedBytes
        self.swap = swap
        self.pressure = pressure
    }

    var usedBytes: UInt64 { appBytes + wiredBytes + compressedBytes }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return (Double(usedBytes) / Double(totalBytes)).clampedToUnitInterval
    }

    /// How full the machine is, which is the question the dashboard tile is
    /// really answering. Distinct from `pressure`, which is the kernel's
    /// verdict on whether that fullness is hurting.
    var utilisationBand: MemoryPressure {
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

/// `vm.swapusage`. Swap in use at all is the signal worth watching: it means
/// the compressor stopped being enough and the kernel went to disk.
nonisolated struct SwapUsage: Codable, Sendable, Equatable {
    let totalBytes: UInt64
    let usedBytes: UInt64

    var availableBytes: UInt64 { totalBytes > usedBytes ? totalBytes - usedBytes : 0 }
    var isActive: Bool { usedBytes > 0 }

    static let zero = SwapUsage(totalBytes: 0, usedBytes: 0)
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
