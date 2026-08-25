import OSLog
import Foundation

actor XPCMetricsProvider: MetricsProviding, CrashSimulating, WorkspaceScanning, ServiceIntrospectable {
    nonisolated let source = MetricsSource.xpcService

    private var connection: NSXPCConnection?
    private var sampleInterval: TimeInterval = 1.0
    private var isStarted = false

    private var pushed: MetricSnapshot?
    private var pushedAt: Date?
    private(set) var pushesReceived = 0

    private var scanContinuation: AsyncStream<ScanUpdate>.Continuation?

    private var interruptionReason: String?

    // MARK: - MetricsProviding

    func start(interval: TimeInterval) async {
        sampleInterval = interval
        isStarted = true
        pushed = nil
        pushedAt = nil

        do {
            try await beginMonitoring()
        } catch {
            Log.xpc.error("Initial connect failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() async {
        isStarted = false
        pushed = nil
        pushedAt = nil

        if let connection {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let box = OneShot(continuation)
                let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                    box.resume(returning: ())
                } as? MonitoringServiceProtocol
                guard let proxy else { return box.resume(returning: ()) }
                proxy.stopMonitoring { _ in box.resume(returning: ()) }
            }
        }

        teardown()
        Log.xpc.info("Disconnected from monitoring service")
    }

    func snapshot() async throws -> MetricSnapshot {
        if let reason = interruptionReason {
            interruptionReason = nil
            teardown()
            throw MetricsProviderError.unavailable(reason)
        }

        if let pushed, let pushedAt, Date().timeIntervalSince(pushedAt) < stalenessLimit {
            return pushed
        }

        if connection == nil || !isStarted {
            try await beginMonitoring()
        }
        return try await requestSnapshot()
    }

    func serviceInfo() async throws -> ServiceInfo {
        let connection = activeConnection()

        let payload: Data = try await withCheckedThrowingContinuation { continuation in
            let box = OneShot(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                box.resume(throwing: MetricsProviderError.unavailable(error.localizedDescription))
            } as? MonitoringServiceProtocol

            guard let proxy else {
                return box.resume(throwing: MetricsProviderError.unavailable("Service refused the connection"))
            }
            proxy.serviceInfo { data, failure in
                if let data {
                    box.resume(returning: data)
                } else {
                    box.resume(throwing: MetricsProviderError.unavailable(failure ?? "Service returned no info"))
                }
            }
        }

        do {
            return try JSONDecoder().decode(ServiceInfo.self, from: payload)
        } catch {
            throw MetricsProviderError.decodingFailed(error.localizedDescription)
        }
    }

    func addressSpaceMap() async throws -> AddressSpaceMap {
        let connection = activeConnection()

        let payload: Data = try await withCheckedThrowingContinuation { continuation in
            let box = OneShot(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                box.resume(throwing: MetricsProviderError.unavailable(error.localizedDescription))
            } as? MonitoringServiceProtocol

            guard let proxy else {
                return box.resume(throwing: MetricsProviderError.unavailable("Service refused the connection"))
            }
            proxy.addressSpaceMap { data, failure in
                if let data {
                    box.resume(returning: data)
                } else {
                    box.resume(throwing: MetricsProviderError.unavailable(failure ?? "Service returned no map"))
                }
            }
        }

        do {
            return try JSONDecoder().decode(AddressSpaceMap.self, from: payload)
        } catch {
            throw MetricsProviderError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - WorkspaceScanning

    func scanUpdates() -> AsyncStream<ScanUpdate> {
        AsyncStream { continuation in
            self.scanContinuation = continuation
        }
    }

    func startScan(path: String) async throws {
        let connection = activeConnection()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = OneShot(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                box.resume(throwing: MetricsProviderError.unavailable(error.localizedDescription))
            } as? MonitoringServiceProtocol

            guard let proxy else {
                return box.resume(throwing: MetricsProviderError.unavailable("Service refused the connection"))
            }
            proxy.startWorkspaceScan(path: path) { _ in
                box.resume(returning: ())
            }
        }
    }

    func cancelScan() async {
        guard let connection else { return }
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            Log.xpc.error("Scan cancel failed: \(error.localizedDescription, privacy: .public)")
        }
        (proxy as? MonitoringServiceProtocol)?.cancelWorkspaceScan()
    }

    private func receiveScan(_ payload: Data) {
        do {
            scanContinuation?.yield(try JSONDecoder().decode(ScanUpdate.self, from: payload))
        } catch {
            Log.xpc.error("Scan update rejected: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - CrashSimulating

    func simulateCrash() async {
        guard let connection else { return }
        Log.xpc.notice("Asking the monitoring service to terminate itself")
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            Log.xpc.error("simulateCrash send failed: \(error.localizedDescription, privacy: .public)")
        }
        (proxy as? MonitoringServiceProtocol)?.simulateCrash()
    }

    // MARK: - Connection

    private var stalenessLimit: TimeInterval { Swift.max(sampleInterval * 2, 1.0) }

    private func beginMonitoring() async throws {
        let connection = activeConnection()
        isStarted = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = OneShot(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                box.resume(throwing: MetricsProviderError.unavailable(error.localizedDescription))
            } as? MonitoringServiceProtocol

            guard let proxy else {
                return box.resume(throwing: MetricsProviderError.unavailable("Service refused the connection"))
            }
            proxy.startMonitoring(interval: sampleInterval) { _ in
                box.resume(returning: ())
            }
        }
    }

    private func requestSnapshot() async throws -> MetricSnapshot {
        let connection = activeConnection()

        let payload: Data = try await withCheckedThrowingContinuation { continuation in
            let box = OneShot(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                box.resume(throwing: MetricsProviderError.unavailable(error.localizedDescription))
            } as? MonitoringServiceProtocol

            guard let proxy else {
                return box.resume(throwing: MetricsProviderError.unavailable("Service refused the connection"))
            }
            proxy.currentSnapshot { data, failure in
                if let data {
                    box.resume(returning: data)
                } else {
                    box.resume(throwing: MetricsProviderError.unavailable(failure ?? "Service returned no snapshot"))
                }
            }
        }

        return try decode(payload)
    }

    private func activeConnection() -> NSXPCConnection {
        if let connection { return connection }

        let connection = NSXPCConnection(serviceName: MonitoringIdentifiers.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: (any MonitoringServiceProtocol).self)

        connection.exportedInterface = NSXPCInterface(with: (any MonitoringClientProtocol).self)
        connection.exportedObject = SnapshotReceiver(
            onSnapshot: { [weak self] payload in
                Task { await self?.receive(payload) }
            },
            onScanUpdate: { [weak self] payload in
                Task { await self?.receiveScan(payload) }
            }
        )

        // Both handlers must be set before resume(), or the callback can be missed.
        // Interruption: peer died, connection reusable. Invalidation: terminal.
        connection.interruptionHandler = { [weak self] in
            Task { await self?.noteFailure("Monitoring service stopped responding") }
        }
        connection.invalidationHandler = { [weak self] in
            Task { await self?.noteFailure("Connection to the monitoring service was invalidated") }
        }

        connection.resume()
        self.connection = connection
        Log.xpc.info("Connected to \(MonitoringIdentifiers.serviceName, privacy: .public)")
        return connection
    }

    private func receive(_ payload: Data) {
        do {
            pushed = try decode(payload)
            pushedAt = Date()
            pushesReceived += 1
        } catch {
            Log.xpc.error("Pushed snapshot rejected: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func noteFailure(_ reason: String) {
        Log.xpc.error("\(reason, privacy: .public)")
        interruptionReason = reason
        pushed = nil
        pushedAt = nil
    }

    private func teardown() {
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        connection = nil
    }

    private func decode(_ payload: Data) throws -> MetricSnapshot {
        let started = Date()
        do {
            var snapshot = try JSONDecoder().decode(MetricSnapshot.self, from: payload)
            snapshot.timing?.decodeStarted = started
            snapshot.timing?.decodeEnded = Date()
            return snapshot
        } catch {
            throw MetricsProviderError.decodingFailed(error.localizedDescription)
        }
    }
}

nonisolated final class SnapshotReceiver: NSObject, MonitoringClientProtocol {
    private let onSnapshot: @Sendable (Data) -> Void
    private let onScanUpdate: @Sendable (Data) -> Void

    init(
        onSnapshot: @escaping @Sendable (Data) -> Void,
        onScanUpdate: @escaping @Sendable (Data) -> Void
    ) {
        self.onSnapshot = onSnapshot
        self.onScanUpdate = onScanUpdate
    }

    func didProduceSnapshot(_ payload: Data) {
        onSnapshot(payload)
    }

    func didUpdateScan(_ payload: Data) {
        onScanUpdate(payload)
    }
}

private nonisolated final class OneShot<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var voidContinuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.voidContinuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let throwing = continuation
        let nonThrowing = voidContinuation
        continuation = nil
        voidContinuation = nil
        lock.unlock()

        throwing?.resume(returning: value)
        nonThrowing?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let throwing = continuation
        continuation = nil
        lock.unlock()

        throwing?.resume(throwing: error)
    }
}
