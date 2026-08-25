import Foundation

nonisolated struct MetricSnapshot: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let cpu: CPUMetrics
    let memory: MemoryMetrics
    let disk: DiskMetrics
    let topProcesses: [ProcessSample]

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

nonisolated struct PipelineTiming: Codable, Sendable, Equatable {
    var collectStarted: Date
    var collectEnded: Date
    var encodeStarted: Date

    var decodeStarted: Date?
    var decodeEnded: Date?
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

    var microseconds: Double { Swift.max(seconds, 0) * 1_000_000 }
}

nonisolated struct CPUMetrics: Codable, Sendable, Equatable {
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
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let freeBytes: UInt64

    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let speculativeBytes: UInt64
    let fileBackedBytes: UInt64
    let swap: SwapUsage

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
