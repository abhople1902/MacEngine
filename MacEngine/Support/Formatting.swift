import Foundation
import SwiftUI

nonisolated extension Double {
    var percentLabel: String {
        formatted(.percent.precision(.fractionLength(0)))
    }

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
    var uptimeLabel: String {
        let total = Int(max(self, 0))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

extension Font {
    static func metricFigure(_ size: CGFloat) -> Font {
        EngineFont.display(size)
    }

    static let engineTitle = EngineFont.display(19)
    static let engineBody = EngineFont.display(12)
    static let metricCaption = EngineFont.display(10)
    static let diagnosticMono = Font.system(size: 11, design: .monospaced)
}
