import SwiftUI

@main
struct MacEngineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(model: appDelegate.dashboard, inspector: appDelegate.inspector)
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
