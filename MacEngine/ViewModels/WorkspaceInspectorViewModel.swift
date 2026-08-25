import OSLog
import SwiftUI
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class WorkspaceInspectorViewModel {
    enum State: Equatable {
        case idle
        case scanning(location: String, completed: Int, total: Int)
        case finished
        case failed(String)

        var isScanning: Bool {
            if case .scanning = self { return true }
            return false
        }

        var fraction: Double {
            guard case let .scanning(_, completed, total) = self, total > 0 else { return 0 }
            return Double(completed) / Double(total)
        }
    }

    private(set) var state: State = .idle
    private(set) var scan: WorkspaceScan?
    private(set) var workspaceName: String?

    var expanded: Set<String> = []

    private let scanner: (any WorkspaceScanning)?
    private var listener: Task<Void, Never>?

    init(scanner: (any WorkspaceScanning)?) {
        self.scanner = scanner
        listenForUpdates()
    }

    var canScan: Bool { scanner != nil }

    // MARK: - Actions

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Xcode project or workspace"
        panel.prompt = "Measure"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false

        let types = ["com.apple.xcode.project", "com.apple.dt.document.workspace"]
            .compactMap { UTType($0) }
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let extensions = ["xcodeproj", "xcworkspace"]
        guard extensions.contains(url.pathExtension) else {
            state = .failed("\(url.lastPathComponent) is not an Xcode project or workspace")
            return
        }

        start(path: url.path)
    }

    func start(path: String) {
        guard let scanner else { return }
        workspaceName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        state = .scanning(location: "Starting", completed: 0, total: 1)

        Task {
            do {
                try await scanner.startScan(path: path)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        guard let scanner else { return }
        Task { await scanner.cancelScan() }
    }

    func toggle(_ node: DiskUsageNode) {
        if expanded.contains(node.id) {
            expanded.remove(node.id)
        } else {
            expanded.insert(node.id)
        }
    }

    // MARK: - Updates

    private func listenForUpdates() {
        guard let scanner else { return }
        listener = Task { [weak self] in
            let stream = await scanner.scanUpdates()
            for await update in stream {
                guard let self else { return }
                self.apply(update)
            }
        }
    }

    private func apply(_ update: ScanUpdate) {
        switch update {
        case .started:
            state = .scanning(location: "Locating DerivedData", completed: 0, total: 1)
        case let .progress(location, completed, total):
            state = .scanning(location: location, completed: completed, total: total)
        case let .finished(result):
            scan = result
            state = .finished
            Log.metrics.info("Scan finished: \(result.totalBytes) bytes across \(result.sections.count) locations")
        case let .failed(reason):
            state = .failed(reason)
        case .cancelled:
            state = scan == nil ? .idle : .finished
        }
    }
}
