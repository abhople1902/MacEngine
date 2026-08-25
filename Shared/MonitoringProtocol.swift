import Foundation

nonisolated enum MonitoringIdentifiers {
    static let serviceName = "com.AyushBhople.MacEngine.MonitoringService"
    static let agentServiceName = "com.AyushBhople.MacEngine.HealthAgent"
    static let diagnosticSocketPath = "/tmp/macengine-diagnostic.sock"
}

@objc nonisolated protocol MonitoringServiceProtocol {
    func currentSnapshot(withReply reply: @escaping (Data?, String?) -> Void)

    func startMonitoring(interval: Double, withReply reply: @escaping (Bool) -> Void)

    func stopMonitoring(withReply reply: @escaping (Bool) -> Void)

    func serviceInfo(withReply reply: @escaping (Data?, String?) -> Void)

    func addressSpaceMap(withReply reply: @escaping (Data?, String?) -> Void)

    func simulateCrash()

    func startWorkspaceScan(path: String, withReply reply: @escaping (Bool) -> Void)

    func cancelWorkspaceScan()
}

@objc nonisolated protocol MonitoringClientProtocol {
    func didProduceSnapshot(_ payload: Data)

    func didUpdateScan(_ payload: Data)
}

nonisolated struct ServiceInfo: Codable, Sendable, Equatable {
    let processIdentifier: Int32
    let startedAt: Date
    let samplesTaken: Int
    let isMonitoring: Bool
    let sampleInterval: TimeInterval

    var diagnosticSocketPath: String?

    var uptime: TimeInterval { Date().timeIntervalSince(startedAt) }
}
