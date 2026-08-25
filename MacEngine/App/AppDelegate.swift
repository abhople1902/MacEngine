import OSLog
import AppKit
import Observation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dashboard: DashboardViewModel
    let inspector: WorkspaceInspectorViewModel

    private var statusItemController: StatusItemController?

    override init() {
        let provider = XPCMetricsProvider()
        dashboard = DashboardViewModel(provider: provider)
        inspector = WorkspaceInspectorViewModel(scanner: provider)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("MacEngine launched, pid \(ProcessInfo.processInfo.processIdentifier)")

        NSApp.appearance = NSAppearance(named: .darkAqua)
        EngineFont.prepare()

        statusItemController = StatusItemController(
            onToggle: { [weak self] in self?.dashboard.toggle() },
            onShowWindow: { [weak self] in self?.showMainWindow() }
        )
        observeLatestSnapshot()
        startScanIfRequested()
    }

    private func startScanIfRequested() {
        guard let path = UserDefaults.standard.string(forKey: "scanPath") else { return }
        Log.app.info("Launch argument requested a scan of \(path, privacy: .public)")
        inspector.start(path: path)
    }

    func applicationWillTerminate(_ notification: Notification) {
        dashboard.stop()
        Log.app.info("MacEngine terminating")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    private func observeLatestSnapshot() {
        withObservationTracking {
            _ = dashboard.latest
            _ = dashboard.connectionState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.statusItemController?.update(
                    snapshot: self.dashboard.latest,
                    state: self.dashboard.connectionState
                )
                self.observeLatestSnapshot()
            }
        }
    }
}
