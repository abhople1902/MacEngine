//
//  Formatting.swift
//  MacEngine
//
//  Display helpers. Everything uses the system font stack — SF Pro for text and
//  SF Mono for figures — so there is nothing to bundle and nothing to license.
//

import Foundation
import SwiftUI

nonisolated extension Double {
    /// 0.324 -> "32%"
    var percentLabel: String {
        formatted(.percent.precision(.fractionLength(0)))
    }

    /// 0.324 -> "32.4%"
    var precisePercentLabel: String {
        formatted(.percent.precision(.fractionLength(1)))
    }
}

nonisolated extension UInt64 {
    var byteLabel: String {
        Int64(clamping: self).formatted(.byteCount(style: .memory))
    }
}

nonisolated extension TimeInterval {
    /// 8071 -> "02:14:31"
    var uptimeLabel: String {
        let total = Int(max(self, 0))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

extension Font {
    /// Figures that change every tick, sized so they do not jitter.
    static func metricFigure(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded).monospacedDigit()
    }

    static let metricCaption = Font.system(.caption, design: .default)
    static let diagnosticMono = Font.system(.caption, design: .monospaced)
}
