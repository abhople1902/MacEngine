//
//  WorkspaceScanner.swift
//  MonitoringService
//
//  Runs the workspace measurement in the service rather than the app.
//
//  Two reasons, and the second is the one that matters. Walking ten gigabytes
//  of metadata would make the dashboard stutter if it ran on the app's side.
//  And keeping it here means the profiling target in block G is a process that
//  does nothing but work, so the Time Profiler trace is not two-thirds SwiftUI.
//

import OSLog
import Foundation

actor WorkspaceScanner {
    private let collector: MetricsCollector
    private var channel: ClientChannel?
    private var running: Task<Void, Never>?

    init(collector: MetricsCollector) {
        self.collector = collector
    }

    var isScanning: Bool { running != nil }

    /// The channel arrives with the request rather than being attached when the
    /// connection is accepted. Attaching separately meant the accept-time hop
    /// onto this actor could still be in flight when the first scan began, and
    /// a one-shot `.started` sent before it landed was dropped silently. Taking
    /// it here also means results go back to whoever actually asked.
    func start(path: String, channel: ClientChannel) {
        self.channel = channel

        // A second request supersedes the first rather than queueing behind it:
        // the user picked a different project, they do not want the old answer.
        running?.cancel()

        running = Task { [weak self] in
            await self?.run(path: path)
        }
    }

    func cancel() {
        running?.cancel()
        running = nil
        emit(.cancelled)
    }

    private func run(path: String) async {
        let startedAt = Date()
        let workspace = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: workspace.path) else {
            emit(.failed(reason: "No project at \(workspace.lastPathComponent)"))
            running = nil
            return
        }

        emit(.started(workspacePath: workspace.path))
        Log.metrics.info("Workspace scan started for \(workspace.lastPathComponent, privacy: .public)")

        // A .xcodeproj is a bundle, so the project itself is its parent folder.
        let projectDirectory = workspace.deletingLastPathComponent()
        let derivedData = WorkspaceLocator.derivedData(forWorkspaceAt: workspace)

        if derivedData == nil {
            Log.metrics.info("No DerivedData folder claims this workspace yet")
        }

        let locations = DeveloperFolders.locations(
            projectDirectory: projectDirectory,
            derivedData: derivedData
        )

        var sections: [ScanSection] = []
        sections.reserveCapacity(locations.count)

        for (offset, location) in locations.enumerated() {
            if Task.isCancelled {
                emit(.cancelled)
                running = nil
                return
            }

            emit(.progress(location: location.name, completed: offset, total: locations.count))

            let exists = FileManager.default.fileExists(atPath: location.url.path)
            let node = await DiskWalker.scan(location.url, name: location.name)

            sections.append(ScanSection(
                category: location.category,
                node: node,
                note: location.note,
                isReclaimable: location.isReclaimable,
                isAbsent: !exists
            ))
        }

        guard !Task.isCancelled else {
            emit(.cancelled)
            running = nil
            return
        }

        let scan = WorkspaceScan(
            workspacePath: workspace.path,
            workspaceName: workspace.deletingPathExtension().lastPathComponent,
            derivedDataPath: derivedData?.path,
            sections: sections.sorted { $0.node.byteCount > $1.node.byteCount },
            toolchain: await collector.toolchainFootprint(),
            startedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt)
        )

        Log.metrics.info("Workspace scan finished in \(scan.duration, format: .fixed(precision: 3))s")
        emit(.finished(scan))
        running = nil
    }

    private func emit(_ update: ScanUpdate) {
        guard let channel else { return }
        do {
            channel.sendScanUpdate(try JSONEncoder().encode(update))
        } catch {
            Log.xpc.error("Scan update encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
