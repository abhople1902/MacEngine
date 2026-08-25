import OSLog
import AppKit
import SwiftUI

// MARK: - Load state

enum SystemLoad: Equatable {
    case nominal
    case elevated
    case pressured

    static func reading(_ snapshot: MetricSnapshot?) -> SystemLoad {
        guard let snapshot else { return .nominal }

        let fromCPU: SystemLoad = switch snapshot.cpu.busyFraction {
        case ..<0.60: .nominal
        case ..<0.85: .elevated
        default: .pressured
        }

        return [fromCPU,
                SystemLoad(snapshot.memory.utilisationBand),
                SystemLoad(snapshot.memory.pressure)]
            .reduce(.nominal, max)
    }

    private init(_ band: MemoryPressure) {
        switch band {
        case .normal: self = .nominal
        case .warning: self = .elevated
        case .critical: self = .pressured
        }
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

enum Theme {
    static let ground = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let surface = Color(red: 0.078, green: 0.086, blue: 0.098)
    static let sunk = Color(red: 0.031, green: 0.035, blue: 0.043)
    static let hairline = Color.white.opacity(0.09)

    static let ink = Color(red: 0.898, green: 0.914, blue: 0.937)
    static let inkSecondary = Color(red: 0.612, green: 0.643, blue: 0.702)
    static let inkTertiary = Color(red: 0.404, green: 0.435, blue: 0.494)

    static let green = Color(red: 0.259, green: 0.855, blue: 0.545)
    static let amber = Color(red: 0.949, green: 0.769, blue: 0.286)
    static let ember = Color(red: 0.965, green: 0.451, blue: 0.310)

    static let cpu = Color(red: 0.376, green: 0.706, blue: 0.996)
    static let memory = Color(red: 0.663, green: 0.573, blue: 0.988)
    static let disk = Color(red: 0.353, green: 0.796, blue: 0.812)
}

// MARK: - Load wash

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

enum EngineFont {
    static let postScriptName = "Audiowide-Regular"

    private static let isAvailable: Bool = {
        if NSFont(name: postScriptName, size: 12) != nil { return true }
        registerBundledFont()
        return NSFont(name: postScriptName, size: 12) != nil
    }()

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
        // Registered at runtime: Xcode does not propagate
        // INFOPLIST_KEY_ATSApplicationFontsPath into the generated Info.plist.
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let reason = error?.takeRetainedValue().localizedDescription ?? "unknown"
            Log.app.error("Audiowide could not be registered: \(reason, privacy: .public)")
        }
    }
}
