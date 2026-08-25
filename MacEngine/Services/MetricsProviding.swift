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

    func start(interval: TimeInterval) async
    func stop() async

    func snapshot() async throws -> MetricSnapshot
}

nonisolated protocol CrashSimulating {
    func simulateCrash() async
}

nonisolated protocol ServiceIntrospectable {
    func serviceInfo() async throws -> ServiceInfo

    var pushesReceived: Int { get async }

    func addressSpaceMap() async throws -> AddressSpaceMap
}

nonisolated protocol WorkspaceScanning {
    func scanUpdates() async -> AsyncStream<ScanUpdate>
    func startScan(path: String) async throws
    func cancelScan() async
}
