//
//  MetricTileView.swift
//  MacEngine
//

import SwiftUI

/// One headline number with a fill bar and a supporting line.
struct MetricTileView: View {
    let title: String
    let value: String
    let caption: String
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.metricCaption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)

            Text(value)
                .font(.metricFigure(30))
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: value)

            MetricBar(fraction: fraction, tint: tint)

            Text(caption)
                .font(.metricCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(caption)")
    }
}

private struct MetricBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(proxy.size.width * fraction.clampedToUnitInterval, 2))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

#Preview {
    HStack {
        MetricTileView(
            title: "CPU",
            value: "32%",
            caption: "10 cores · 18% user · 14% system",
            fraction: 0.32,
            tint: .blue
        )
        MetricTileView(
            title: "Memory",
            value: "8.4 GB",
            caption: "of 16 GB · normal pressure",
            fraction: 0.52,
            tint: .purple
        )
    }
    .padding()
    .frame(width: 520)
}
