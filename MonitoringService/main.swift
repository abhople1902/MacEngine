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

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // What this process vends.
        newConnection.exportedInterface = NSXPCInterface(with: (any MonitoringServiceProtocol).self)
        newConnection.exportedObject = MonitoringService(collector: collector)

        // What the app vends back to us. Setting this is what makes the
        // connection bidirectional: without it the service could only ever
        // answer requests, never push a snapshot.
        newConnection.remoteObjectInterface = NSXPCInterface(with: (any MonitoringClientProtocol).self)

        let channel = ClientChannel(connection: newConnection)
        Task { await collector.attach(channel) }

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

Log.xpc.info("Monitoring service listening (pid \(ProcessInfo.processInfo.processIdentifier))")

// Does not return.
listener.resume()
