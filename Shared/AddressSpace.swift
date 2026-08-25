import Foundation

nonisolated enum RegionKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case heap
    case stack
    case text
    case mappedFile
    case shared
    case reserved
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heap: "Heap"
        case .stack: "Stack"
        case .text: "__TEXT"
        case .mappedFile: "Mapped files"
        case .shared: "Shared"
        case .reserved: "Reserved"
        case .other: "Other"
        }
    }

    var explanation: String {
        switch self {
        case .heap:
            "Everything malloc handed out — tiny, small, medium, large and nano zones, tagged by the allocator itself."
        case .stack:
            "Thread stacks. Reserved large and touched sparsely, which is why virtual dwarfs resident here."
        case .text:
            "Executable pages backed by a file on disk. Clean, shareable, and evictable without a write."
        case .mappedFile:
            "Non-executable file mappings — resources, caches, anything mmap'd read-only."
        case .shared:
            "Pages shared with other processes rather than owned outright."
        case .reserved:
            "Address space claimed with no access at all. It costs a page-table entry and nothing else — this is why virtual size is not a memory number."
        case .other:
            "Anonymous mappings the allocator did not tag: dylib data segments, the shared cache and framework scratch."
        }
    }
}

nonisolated struct RegionGroup: Codable, Sendable, Equatable, Identifiable {
    let kind: RegionKind
    let regionCount: Int
    let virtualBytes: UInt64
    let residentBytes: UInt64
    let swappedBytes: UInt64

    var id: RegionKind { kind }

    var residency: Double {
        guard virtualBytes > 0 else { return 0 }
        return (Double(residentBytes) / Double(virtualBytes)).clampedToUnitInterval
    }
}

nonisolated struct AddressSpaceMap: Codable, Sendable, Equatable {
    let processIdentifier: Int32
    let processName: String
    let sampledAt: Date
    let groups: [RegionGroup]
    let wasTruncated: Bool

    var regionCount: Int { groups.reduce(0) { $0 + $1.regionCount } }
    var virtualBytes: UInt64 { groups.reduce(0) { $0 &+ $1.virtualBytes } }
    var residentBytes: UInt64 { groups.reduce(0) { $0 &+ $1.residentBytes } }
    var swappedBytes: UInt64 { groups.reduce(0) { $0 &+ $1.swappedBytes } }

    var significantGroups: [RegionGroup] {
        groups
            .filter { $0.regionCount > 0 }
            .sorted { $0.residentBytes > $1.residentBytes }
    }
}
