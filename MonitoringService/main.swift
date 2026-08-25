//
//  main.swift
//  MonitoringService
//
//  Entry point for the monitoring process. One listener, one collector, and one
//  exported object per incoming connection.
//

import OSLog
import Foundation

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    /// Shared across connections so sampling state and counters belong to the
    /// process, not to whoever happened to connect.
    private let collector = MetricsCollector()
    private lazy var scanner = WorkspaceScanner(collector: collector)

    /// The non-XPC way in. Opened once, for the life of the process.
    private lazy var diagnostics = DiagnosticSocket(collector: collector)

    func openDiagnosticSocket() {
        diagnostics.start()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // What this process vends.
        newConnection.exportedInterface = NSXPCInterface(with: (any MonitoringServiceProtocol).self)
        let channel = ClientChannel(connection: newConnection)
        newConnection.exportedObject = MonitoringService(
            collector: collector,
            scanner: scanner,
            channel: channel
        )

        // What the app vends back to us. Setting this is what makes the
        // connection bidirectional: without it the service could only ever
        // answer requests, never push a snapshot.
        newConnection.remoteObjectInterface = NSXPCInterface(with: (any MonitoringClientProtocol).self)

        Task { [collector] in await collector.attach(channel) }

        newConnection.invalidationHandler = {
            Log.xpc.info("Client connection invalidated")
        }

        newConnection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate

// Opened before the listener resumes, so a CLI can reach the service during
// whatever the first XPC client is doing rather than only afterwards.
delegate.openDiagnosticSocket()

Log.xpc.info("Monitoring service listening (pid \(ProcessInfo.processInfo.processIdentifier))")

// Does not return.
listener.resume()
