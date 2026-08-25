import Foundation

nonisolated struct DiskUsageNode: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let path: String
    let byteCount: UInt64
    let fileCount: Int
    let children: [DiskUsageNode]

    var id: String { path }

    init(name: String, path: String, byteCount: UInt64, fileCount: Int, children: [DiskUsageNode] = []) {
        self.name = name
        self.path = path
        self.byteCount = byteCount
        self.fileCount = fileCount
        self.children = children
    }
}

nonisolated enum ScanCategory: String, Codable, Sendable, CaseIterable {
    case project
    case derivedData
    case sharedCache
    case simulator
    case deviceSupport
    case archives
    case packages

    var title: String {
        switch self {
        case .project: "This project"
        case .derivedData: "DerivedData"
        case .sharedCache: "Shared caches"
        case .simulator: "Simulators"
        case .deviceSupport: "Device support"
        case .archives: "Archives"
        case .packages: "Packages"
        }
    }
}

nonisolated struct ScanSection: Codable, Sendable, Equatable, Identifiable {
    let category: ScanCategory
    let node: DiskUsageNode
    let note: String
    let isReclaimable: Bool
    let isAbsent: Bool

    var id: String { node.path }
}

nonisolated struct WorkspaceScan: Codable, Sendable, Equatable {
    let workspacePath: String
    let workspaceName: String
    let derivedDataPath: String?
    let sections: [ScanSection]
    let toolchain: ToolchainFootprint
    let startedAt: Date
    let duration: TimeInterval

    var totalBytes: UInt64 {
        sections.reduce(0) { $0 + $1.node.byteCount }
    }

    var reclaimableBytes: UInt64 {
        sections.filter(\.isReclaimable).reduce(0) { $0 + $1.node.byteCount }
    }
}

nonisolated struct ToolchainFootprint: Codable, Sendable, Equatable {
    let groups: [ToolchainGroup]

    var totalBytes: UInt64 { groups.reduce(0) { $0 + $1.memoryBytes } }
    var processCount: Int { groups.reduce(0) { $0 + $1.processCount } }

    static let empty = ToolchainFootprint(groups: [])
}

nonisolated struct ToolchainGroup: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let processCount: Int
    let memoryBytes: UInt64
    let cpuFraction: Double

    var id: String { name }
}

nonisolated enum ScanUpdate: Codable, Sendable, Equatable {
    case started(workspacePath: String)
    case progress(location: String, completed: Int, total: Int)
    case finished(WorkspaceScan)
    case failed(reason: String)
    case cancelled
}
