//
//  MacEngineApp.swift
//  MacEngine
//
//  Created by Ayush Bhople on 20/08/26.
//

import SwiftUI

@main
struct MacEngineApp: App {
    // AppKit owns the app lifecycle: the delegate builds the menu bar item and
    // holds the dashboard model that both the window and the status item read.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(model: appDelegate.dashboard)
        }
        .defaultSize(width: 820, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Monitoring") {
                Button(appDelegate.dashboard.connectionState == .idle ? "Start" : "Stop") {
                    appDelegate.dashboard.toggle()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Clear History") {
                    appDelegate.dashboard.clearHistory()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}
