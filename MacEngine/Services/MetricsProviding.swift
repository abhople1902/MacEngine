//
//  MetricsProviding.swift
//  MacEngine
//
//  The seam that keeps the UI honest. In Block A the only implementation
//  samples in-process; in Block B `XPCMetricsProvider` dials the monitoring
//  service and nothing above this protocol changes.
//

import Foundation

nonisolated enum MetricsSource: String, Sendable, Equatable {
    case local
    case xpcService

    var displayName: String {
        switch self {
        case .local: "In-process sampler"
        case .xpcService: "Monitoring service (XPC)"
        }
    }

    /// Whether readings come from a separate process that can fail independently.
    var isolatesFailure: Bool { self == .xpcService }
}

nonisolated enum MetricsProviderError: LocalizedError, Equatable {
    case unavailable(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .decodingFailed(let reason): "Could not decode a snapshot: \(reason)"
        }
    }
}

nonisolated protocol MetricsProviding: Sendable {
    nonisolated var source: MetricsSource { get }

    /// Begins sampling. Safe to call when already started.
    func start(interval: TimeInterval) async
    func stop() async

    /// One reading, taken now.
    func snapshot() async throws -> MetricSnapshot
}

/// Implemented only by providers whose work happens in another process, because
/// only they have a process worth killing. The Diagnostics control is hidden
/// when the active provider does not conform.
nonisolated protocol CrashSimulating {
    /// Terminates the backing process so the recovery path can be observed.
    func simulateCrash() async
}

/// Implemented by providers backed by a separate process, so Engineer Mode can
/// name that process and show how the connection to it is behaving. The local
/// provider deliberately does not conform — it has no peer to describe.
nonisolated protocol ServiceIntrospectable {
    /// Health and identity of the backing process, asked for directly rather
    /// than inferred, so a recovered service is distinguishable from one that
    /// never died.
    func serviceInfo() async throws -> ServiceInfo

    /// Snapshots that arrived unsolicited. Non-zero is the only direct evidence
    /// the reverse half of the connection is live.
    var pushesReceived: Int { get async }

    /// The backing process's own address space, walked by that process.
    func addressSpaceMap() async throws -> AddressSpaceMap
}

/// Implemented by providers that can measure a workspace's cost on disk. Kept
/// separate from `MetricsProviding` because a scan is a different shape of work
/// — one long job with progress, not a repeating reading.
nonisolated protocol WorkspaceScanning {
    /// Progress and results for scans. One consumer; the stream lives as long
    /// as the provider does.
    func scanUpdates() async -> AsyncStream<ScanUpdate>
    func startScan(path: String) async throws
    func cancelScan() async
}
