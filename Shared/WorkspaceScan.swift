//
//  WorkspaceScan.swift
//  Shared
//
//  Wire format for the Xcode Workspace Inspector. A scan crosses XPC the same
//  way metrics do — JSON-encoded Codable values as Data — but unlike metrics it
//  is a long-running job, so progress and the final result both arrive over the
//  reverse channel rather than as a reply to a request.
//

import Foundation

/// One measured directory. Children are one level deep: measuring the whole
/// tree recursively would cost far more than the breakdown is worth.
nonisolated struct DiskUsageNode: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let path: String
    let byteCount: UInt64
    let fileCount: Int
    let children: [DiskUsageNode]

    /// Paths are unique and stable across rescans; a fresh UUID would make
    /// SwiftUI treat every row as new on each update.
    var id: String { path }

    init(name: String, path: String, byteCount: UInt64, fileCount: Int, children: [DiskUsageNode] = []) {
        self.name = name
        self.path = path
        self.byteCount = byteCount
        self.fileCount = fileCount
        self.children = children
    }
}

/// What a measured location means, which is the difference between "safe to
/// delete" and "you will re-download Xcode".
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
    /// What this location is, in the terms someone deciding whether to delete it
    /// would want. Carried per location rather than per category because
    /// ModuleCache and UserData are both caches and only one is safe to remove.
    let note: String
    /// True when deleting it costs rebuild time and nothing else.
    let isReclaimable: Bool
    /// Set when the location does not exist on this machine. Empty locations are
    /// still reported, because they are the ones that explode elsewhere.
    let isAbsent: Bool

    var id: String { node.path }
}

nonisolated struct WorkspaceScan: Codable, Sendable, Equatable {
    let workspacePath: String
    let workspaceName: String
    /// nil when no DerivedData folder claims this workspace.
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

/// Live memory cost of the toolchain serving this project, grouped by
/// executable so twelve swift-frontend processes read as one line.
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

/// Everything the service reports while a scan is running.
nonisolated enum ScanUpdate: Codable, Sendable, Equatable {
    case started(workspacePath: String)
    case progress(location: String, completed: Int, total: Int)
    case finished(WorkspaceScan)
    case failed(reason: String)
    case cancelled
}
