//
//  StatusItemController.swift
//  MacEngine
//
//  The menu bar readout — a plain NSStatusItem with an NSMenu, driven from the
//  same view model the SwiftUI window uses.
//

import AppKit

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let toggleMenuItem = NSMenuItem(
        title: "Stop Monitoring",
        action: #selector(handleToggle),
        keyEquivalent: "r"
    )
    private let onToggle: () -> Void
    private let onShowWindow: () -> Void
    private var themeObserver: NSObjectProtocol?

    init(onToggle: @escaping () -> Void, onShowWindow: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onShowWindow = onShowWindow
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        configureMenu()
        observeInterfaceStyle()
    }

    deinit {
        MainActor.assumeIsolated {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        if let themeObserver {
            DistributedNotificationCenter.default().removeObserver(themeObserver)
        }
    }

    func update(snapshot: MetricSnapshot?, state: DashboardViewModel.ConnectionState) {
        guard let button = statusItem.button else { return }

        if let snapshot {
            button.attributedTitle = Self.title(for: snapshot.cpu.busyFraction)
            button.toolTip = """
                CPU \(snapshot.cpu.busyFraction.precisePercentLabel)
                Memory \(snapshot.memory.usedBytes.byteLabel) of \(snapshot.memory.totalBytes.byteLabel)
                """
        } else {
            button.attributedTitle = Self.title(for: nil)
            button.toolTip = state.label
        }

        toggleMenuItem.title = state == .idle ? "Start Monitoring" : "Stop Monitoring"
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.33percent",
            accessibilityDescription: "MacEngine"
        )
        button.imagePosition = .imageLeading
        button.attributedTitle = Self.title(for: nil)
        applyMenuBarAppearance()
    }

    /// The window is pinned to dark, and `NSApp.appearance` is what pins it.
    /// The status item is not ours to restyle, though — it sits in the user's
    /// menu bar — so it opts back out to whatever the system is set to.
    private func applyMenuBarAppearance() {
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        statusItem.button?.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    private func observeInterfaceStyle() {
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyMenuBarAppearance()
            }
        }
    }

    private func configureMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Open MacEngine", action: #selector(handleShow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit MacEngine", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )

        statusItem.menu = menu
    }

    @objc private func handleToggle() {
        onToggle()
    }

    @objc private func handleShow() {
        onShowWindow()
    }

    /// Monospaced digits so the menu bar does not shuffle on every tick.
    private static func title(for fraction: Double?) -> NSAttributedString {
        let text = fraction.map { " \($0.percentLabel)" } ?? " —"
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            ]
        )
    }
}
