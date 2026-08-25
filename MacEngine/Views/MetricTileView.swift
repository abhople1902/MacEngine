import SwiftUI

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
                .foregroundStyle(Theme.inkSecondary)
                .textCase(.uppercase)
                .kerning(1.2)

            Text(value)
                .font(.metricFigure(26))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            MetricBar(fraction: fraction, tint: tint)

            Text(caption)
                .font(.metricCaption)
                .foregroundStyle(Theme.inkTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panel()
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
                    .fill(Theme.sunk)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(proxy.size.width * fraction.clampedToUnitInterval, 2))
                    .shadow(color: tint.opacity(0.55), radius: 4)
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
            tint: Theme.cpu
        )
        MetricTileView(
            title: "Memory",
            value: "8.4 GB",
            caption: "of 16 GB · normal pressure",
            fraction: 0.52,
            tint: Theme.memory
        )
    }
    .padding()
    .frame(width: 520)
    .background(LoadWash(load: .nominal))
}
