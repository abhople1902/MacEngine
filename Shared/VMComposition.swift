//
//  VMComposition.swift
//  Shared
//
//  The stacked bar Engineer Mode draws, and the vocabulary that goes with it.
//  Every segment is a state the Darwin VM actually keeps pages in, so the bar
//  is a readout rather than an illustration.
//

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

    /// One sentence per state, because a bar with seven unexplained colours is
    /// decoration and a bar with seven explained ones is a systems answer.
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
    /// The six counters plus their remainder, always summing to `totalBytes`.
    ///
    /// Showing the remainder rather than normalising it away is the point: the
    /// counters are sampled independently and will not agree exactly, and
    /// silently scaling them to fit would hide that.
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

    /// How much of installed RAM the named counters explain, 0...1. A value
    /// far from 1 means the sample is not trustworthy.
    var compositionCoverage: Double {
        guard totalBytes > 0 else { return 0 }
        let accounted = composition
            .filter { $0.state != .unaccounted }
            .reduce(UInt64(0)) { $0 &+ $1.bytes }
        return (Double(accounted) / Double(totalBytes)).clampedToUnitInterval
    }
}
