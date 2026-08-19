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
