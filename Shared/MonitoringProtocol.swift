//
//  MonitoringProtocol.swift
//  Shared
//
//  The XPC contract. Declared here in Block A so the app, the service and the
//  CLI all compile against one definition once the service target lands.
//
//  NSXPCConnection requires an @objc nonisolated protocol whose parameters are Objective-C
//  representable, so payloads cross as `Data` holding JSON-encoded `Codable`
//  values rather than as `NSSecureCoding` classes.
//

import Foundation

/// Identifiers shared by every process in the system.
nonisolated enum MonitoringIdentifiers {
    /// Bundle identifier of the XPC service, and the name the app dials.
    static let serviceName = "com.AyushBhople.MacEngine.MonitoringService"
    /// Mach service name used by the background health agent.
    static let agentServiceName = "com.AyushBhople.MacEngine.HealthAgent"
    /// Filesystem path of the diagnostic Unix domain socket.
    static let diagnosticSocketPath = "/tmp/macengine-diagnostic.sock"
}

@objc nonisolated protocol MonitoringServiceProtocol {
    /// Returns one JSON-encoded `MetricSnapshot`, or an error description.
    func currentSnapshot(withReply reply: @escaping (Data?, String?) -> Void)

    /// Starts periodic sampling inside the service at `interval` seconds.
    func startMonitoring(interval: Double, withReply reply: @escaping (Bool) -> Void)

    func stopMonitoring(withReply reply: @escaping (Bool) -> Void)

    /// Returns one JSON-encoded `ServiceInfo` describing service health.
    func serviceInfo(withReply reply: @escaping (Data?, String?) -> Void)

    /// Returns one JSON-encoded `AddressSpaceMap` of the *service's own* task.
    /// The service has to map itself because the app cannot: reading another
    /// process's VM regions needs `task_for_pid`, which needs privileges this
    /// project does not take.
    func addressSpaceMap(withReply reply: @escaping (Data?, String?) -> Void)

    /// Debug-only: terminates the service so the app's recovery path can be
    /// exercised from the Diagnostics screen.
    func simulateCrash()

    /// Begins measuring a workspace's true cost on disk. Returns as soon as the
    /// job is accepted — a full walk takes tens of seconds and holding an XPC
    /// reply block open for that long invites a timeout and gives the user no
    /// feedback. Progress and the result arrive over `MonitoringClientProtocol`.
    func startWorkspaceScan(path: String, withReply reply: @escaping (Bool) -> Void)

    func cancelWorkspaceScan()
}

/// Callbacks the service invokes on the app. Streaming metrics travel this way;
/// lifecycle events travel over `DistributedNotificationCenter` instead.
@objc nonisolated protocol MonitoringClientProtocol {
    func didProduceSnapshot(_ payload: Data)

    /// One JSON-encoded `ScanUpdate`: started, progress, finished or failed.
    func didUpdateScan(_ payload: Data)
}

/// Health and lifetime of the monitoring process itself.
nonisolated struct ServiceInfo: Codable, Sendable, Equatable {
    let processIdentifier: Int32
    let startedAt: Date
    let samplesTaken: Int
    let isMonitoring: Bool
    let sampleInterval: TimeInterval

    var uptime: TimeInterval { Date().timeIntervalSince(startedAt) }
}
