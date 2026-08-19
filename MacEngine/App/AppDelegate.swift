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
    let dashboard = DashboardViewModel()

    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("MacEngine launched, pid \(ProcessInfo.processInfo.processIdentifier)")

        statusItemController = StatusItemController(
            onToggle: { [weak self] in self?.dashboard.toggle() },
            onShowWindow: { [weak self] in self?.showMainWindow() }
        )
        observeLatestSnapshot()
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
