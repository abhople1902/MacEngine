//
//  MonitoringService.swift
//  MonitoringService
//
//  The object exported across the XPC connection. It owns no state of its own:
//  every call is forwarded to the shared `MetricsCollector` actor, which is
//  what keeps concurrent calls from several connections safe.
//
//  The protocol is @objc with reply blocks because that is what NSXPCConnection
//  vends, so each method here is the small bridge from a completion handler to
//  the actor's async interface.
//

import OSLog
import Foundation

final class MonitoringService: NSObject, MonitoringServiceProtocol {
    private let collector: MetricsCollector

    init(collector: MetricsCollector) {
        self.collector = collector
    }

    func currentSnapshot(withReply reply: @escaping (Data?, String?) -> Void) {
        Task { [collector] in
            do {
                reply(try JSONEncoder().encode(await collector.snapshot()), nil)
            } catch {
                Log.xpc.error("Snapshot encode failed: \(error.localizedDescription, privacy: .public)")
                reply(nil, error.localizedDescription)
            }
        }
    }

    func startMonitoring(interval: Double, withReply reply: @escaping (Bool) -> Void) {
        Task { [collector] in
            await collector.start(interval: interval)
            reply(true)
        }
    }

    func stopMonitoring(withReply reply: @escaping (Bool) -> Void) {
        Task { [collector] in
            await collector.stop()
            reply(true)
        }
    }

    func serviceInfo(withReply reply: @escaping (Data?, String?) -> Void) {
        Task { [collector] in
            do {
                reply(try JSONEncoder().encode(await collector.info()), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func simulateCrash() {
        Log.xpc.fault("simulateCrash() called - terminating monitoring service")
        // No reply block by design: the process is gone before it could send
        // one, which is precisely the failure the app has to survive. launchd
        // relaunches the service on the next message sent to it.
        exit(EXIT_FAILURE)
    }
}
