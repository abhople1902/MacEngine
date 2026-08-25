//
//  AppDelegate.swift
//  MacEngine
//
//  Cocoa entry point. SwiftUI draws the window, but the application object,
//  the menu bar item and the termination path are all AppKit.
//

import OSLog
import AppKit
import Observation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // The app no longer samples anything itself: readings come from the
    // monitoring service over XPC. `LocalMetricsProvider` remains as the
    // in-process comparison and is what the unit tests drive.
    //
    // One provider, shared. Two would mean two connections to the same service
    // and two sampling loops inside it, for no benefit.
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

        // `.preferredColorScheme` only reaches SwiftUI content. Pinning the
        // application appearance is what makes the title bar, the toolbar and
        // the menu bar item match, whatever the Mac is set to.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        EngineFont.prepare()

        statusItemController = StatusItemController(
            onToggle: { [weak self] in self?.dashboard.toggle() },
            onShowWindow: { [weak self] in self?.showMainWindow() }
        )
        observeLatestSnapshot()
        startScanIfRequested()
    }

    /// `-scanPath <project>` runs a workspace scan straight after launch.
    ///
    /// This exists for profiling, not for users. A before/after number is only
    /// worth publishing if both runs did identical work, and the open panel
    /// cannot be driven from a trace script. `UserDefaults` reads the argument
    /// domain for free, so no argument parsing is needed and nothing persists.
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
        // The menu bar item keeps reporting after the window is closed.
        false
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    /// Re-arms after every change: `withObservationTracking` fires once per
    /// registration, so the status item needs a fresh subscription each tick.
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
