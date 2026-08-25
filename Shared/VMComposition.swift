import Foundation

nonisolated enum VMPageState: String, Codable, Sendable, CaseIterable, Identifiable {
    case wired
    case active
    case inactive
    case speculative
    case compressed
    case free
    case unaccounted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wired: "Wired"
        case .active: "Active"
        case .inactive: "Inactive"
        case .speculative: "Speculative"
        case .compressed: "Compressed"
        case .free: "Free"
        case .unaccounted: "Unaccounted"
        }
    }

    var explanation: String {
        switch self {
        case .wired:
            "Cannot be paged out or compressed. Kernel, drivers and pages a process has locked."
        case .active:
            "Recently used and mapped. First in line to stay resident."
        case .inactive:
            "Resident but not recently touched. Reclaimable without hitting disk if it is file-backed."
        case .speculative:
            "Read ahead of a request the kernel guessed at. Free in practice — it is discarded first."
        case .compressed:
            "Was anonymous memory, now held compressed in RAM. Cheaper than swapping to disk."
        case .free:
            "Not backing anything. On this OS a large free number means idle, not healthy."
        case .unaccounted:
            "Installed RAM the VM system never manages: firmware and kernel carve-outs taken before paging starts — around 6% on this Mac — plus drift between counters read microseconds apart."
        }
    }
}

nonisolated struct VMSegment: Sendable, Equatable, Identifiable {
    let state: VMPageState
    let bytes: UInt64

    var id: VMPageState { state }
}

nonisolated extension MemoryMetrics {
    var composition: [VMSegment] {
        let named: [(VMPageState, UInt64)] = [
            (.wired, wiredBytes),
            (.active, activeBytes),
            (.inactive, inactiveBytes),
            (.speculative, speculativeBytes),
            (.compressed, compressedBytes),
            (.free, freeBytes)
        ]

        let accounted = named.reduce(UInt64(0)) { $0 &+ $1.1 }
        let remainder = totalBytes > accounted ? totalBytes - accounted : 0

        return named.map { VMSegment(state: $0.0, bytes: $0.1) }
            + [VMSegment(state: .unaccounted, bytes: remainder)]
    }

    var compositionCoverage: Double {
        guard totalBytes > 0 else { return 0 }
        let accounted = composition
            .filter { $0.state != .unaccounted }
            .reduce(UInt64(0)) { $0 &+ $1.bytes }
        return (Double(accounted) / Double(totalBytes)).clampedToUnitInterval
    }
}
