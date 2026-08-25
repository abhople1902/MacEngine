import OSLog
import Foundation

final class MonitoringService: NSObject, MonitoringServiceProtocol {
    private let collector: MetricsCollector
    private let scanner: WorkspaceScanner
    private let channel: ClientChannel

    init(collector: MetricsCollector, scanner: WorkspaceScanner, channel: ClientChannel) {
        self.collector = collector
        self.scanner = scanner
        self.channel = channel
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

    func addressSpaceMap(withReply reply: @escaping (Data?, String?) -> Void) {
        do {
            reply(try JSONEncoder().encode(AddressSpaceSampler().sample()), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func startWorkspaceScan(path: String, withReply reply: @escaping (Bool) -> Void) {
        Task { [scanner, channel] in
            await scanner.start(path: path, channel: channel)
            reply(true)
        }
    }

    func cancelWorkspaceScan() {
        Task { [scanner] in
            await scanner.cancel()
        }
    }

    func simulateCrash() {
        Log.xpc.fault("simulateCrash() called - terminating monitoring service")
        exit(EXIT_FAILURE)
    }
}
