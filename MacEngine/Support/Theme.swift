//
//  Theme.swift
//  MacEngine
//
//  MacEngine ships its own dark palette rather than following the system
//  appearance: the readout is an instrument panel, and an instrument panel that
//  turns white at 7am is a worse instrument. The one thing that does change is
//  the wash in the top-right corner, which is tinted by how hard the machine is
//  currently working.
//

import OSLog
import AppKit
import SwiftUI

// MARK: - Load state

/// How hard the machine is working, reduced to the three states worth colouring.
///
/// The reduction is deliberately blunt — the tiles already carry the precise
/// numbers, so this only has to answer "is anything wrong from across the room".
enum SystemLoad: Equatable {
    case nominal
    case elevated
    case pressured

    /// CPU is the fast signal and memory pressure the slow one; the worse of the
    /// two wins so a wedged compiler and a full memory bank both show up.
    static func reading(_ snapshot: MetricSnapshot?) -> SystemLoad {
        guard let snapshot else { return .nominal }

        let fromCPU: SystemLoad = switch snapshot.cpu.busyFraction {
        case ..<0.60: .nominal
        case ..<0.85: .elevated
        default: .pressured
        }

        let fromMemory: SystemLoad = switch snapshot.memory.pressure {
        case .normal: .nominal
        case .warning: .elevated
        case .critical: .pressured
        }

        return max(fromCPU, fromMemory)
    }

    private var severity: Int {
        switch self {
        case .nominal: 0
        case .elevated: 1
        case .pressured: 2
        }
    }

    static func max(_ lhs: SystemLoad, _ rhs: SystemLoad) -> SystemLoad {
        lhs.severity >= rhs.severity ? lhs : rhs
    }

    var tint: Color {
        switch self {
        case .nominal: Theme.green
        case .elevated: Theme.amber
        case .pressured: Theme.ember
        }
    }

    var label: String {
        switch self {
        case .nominal: "NOMINAL"
        case .elevated: "ELEVATED"
        case .pressured: "UNDER PRESSURE"
        }
    }
}

// MARK: - Palette

/// Fixed colours. Nothing here reads the system appearance, by design.
enum Theme {
    /// Window background — near black, warmed very slightly so it does not look
    /// like a hole punched in the desktop.
    static let ground = Color(red: 0.043, green: 0.047, blue: 0.055)
    /// Cards sitting on `ground`.
    static let surface = Color(red: 0.078, green: 0.086, blue: 0.098)
    /// Wells inside cards: chart plots, table bodies, empty bar tracks.
    static let sunk = Color(red: 0.031, green: 0.035, blue: 0.043)
    static let hairline = Color.white.opacity(0.09)

    static let ink = Color(red: 0.898, green: 0.914, blue: 0.937)
    static let inkSecondary = Color(red: 0.612, green: 0.643, blue: 0.702)
    static let inkTertiary = Color(red: 0.404, green: 0.435, blue: 0.494)

    static let green = Color(red: 0.259, green: 0.855, blue: 0.545)
    static let amber = Color(red: 0.949, green: 0.769, blue: 0.286)
    static let ember = Color(red: 0.965, green: 0.451, blue: 0.310)

    /// Per-metric accents, kept cool so the load wash stays the loudest colour
    /// on screen.
    static let cpu = Color(red: 0.376, green: 0.706, blue: 0.996)
    static let memory = Color(red: 0.663, green: 0.573, blue: 0.988)
    static let disk = Color(red: 0.353, green: 0.796, blue: 0.812)
}

// MARK: - Load wash

/// The window background: flat `ground` with a soft corner light whose colour
/// tracks `load`. Kept low-contrast on purpose — it should register peripherally
/// and never compete with the figures.
struct LoadWash: View {
    let load: SystemLoad

    var body: some View {
        Theme.ground
            .overlay(alignment: .topTrailing) {
                GeometryReader { proxy in
                    let diameter = Swift.max(proxy.size.width, proxy.size.height) * 1.05

                    RadialGradient(
                        colors: [
                            load.tint.opacity(0.26),
                            load.tint.opacity(0.09),
                            load.tint.opacity(0)
                        ],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: diameter
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blendMode(.plusLighter)
                }
            }
            .animation(.easeInOut(duration: 0.9), value: load)
            .ignoresSafeArea()
    }
}

// MARK: - Card chrome

/// Every panel in the app is the same rounded, hairlined surface.
struct PanelBackground: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(Theme.surface.opacity(0.72), in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
    }
}

extension View {
    func panel(cornerRadius: CGFloat = 12) -> some View {
        modifier(PanelBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Typography

/// Audiowide is bundled in `Contents/Resources` and registered with
/// CoreText at launch. Registering it in code rather than through
/// `ATSApplicationFontsPath` keeps it working in previews and in any host that
/// is not the built app bundle; every call site still falls back to the system
/// face if the file is genuinely missing, so a bad copy phase degrades instead
/// of rendering blank.
enum EngineFont {
    static let postScriptName = "Audiowide-Regular"

    private static let isAvailable: Bool = {
        if NSFont(name: postScriptName, size: 12) != nil { return true }
        registerBundledFont()
        return NSFont(name: postScriptName, size: 12) != nil
    }()

    /// Call once at launch so the first text drawn already has the face.
    static func prepare() {
        _ = isAvailable
    }

    static func display(_ size: CGFloat) -> Font {
        isAvailable ? .custom(postScriptName, fixedSize: size) : .system(size: size, weight: .medium)
    }

    private static func registerBundledFont() {
        guard let url = Bundle.main.url(forResource: "Audiowide-Regular", withExtension: "ttf") else {
            Log.app.error("Audiowide-Regular.ttf is not in the app bundle")
            return
        }

        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let reason = error?.takeRetainedValue().localizedDescription ?? "unknown"
            Log.app.error("Audiowide could not be registered: \(reason, privacy: .public)")
        }
    }
}
