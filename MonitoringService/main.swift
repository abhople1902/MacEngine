import OSLog
import Foundation

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let collector = MetricsCollector()
    private lazy var scanner = WorkspaceScanner(collector: collector)

    private lazy var diagnostics = DiagnosticSocket(collector: collector)

    func openDiagnosticSocket() {
        diagnostics.start()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: (any MonitoringServiceProtocol).self)
        let channel = ClientChannel(connection: newConnection)
        newConnection.exportedObject = MonitoringService(
            collector: collector,
            scanner: scanner,
            channel: channel
        )

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

delegate.openDiagnosticSocket()

Log.xpc.info("Monitoring service listening (pid \(ProcessInfo.processInfo.processIdentifier))")

listener.resume()
