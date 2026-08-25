import SwiftUI

struct VMCompositionView: View {
    let memory: MemoryMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            bar
            legend
            Divider().overlay(Theme.hairline)
            verdict
        }
    }

    // MARK: - Bar

    private var bar: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(memory.composition) { segment in
                    Rectangle()
                        .fill(segment.state.tint)
                        .frame(width: width(of: segment, in: proxy.size.width))
                }
            }
        }
        .frame(height: 22)
        .clipShape(.rect(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.4), value: memory)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func width(of segment: VMSegment, in total: CGFloat) -> CGFloat {
        guard memory.totalBytes > 0, segment.bytes > 0 else { return 0 }
        let exact = total * CGFloat(Double(segment.bytes) / Double(memory.totalBytes))
        return max(exact, 3)
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(memory.composition) { segment in
                HStack(alignment: .top, spacing: 9) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segment.state.tint)
                        .frame(width: 9, height: 9)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 8) {
                            Text(segment.state.title)
                                .font(.engineBody)
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: 12)
                            Text(fractionLabel(segment))
                                .font(.diagnosticMono)
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(width: 52, alignment: .trailing)
                            Text(segment.bytes.byteLabel)
                                .font(.metricFigure(13))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 74, alignment: .trailing)
                        }
                        Text(segment.state.explanation)
                            .font(.metricCaption)
                            .foregroundStyle(Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func fractionLabel(_ segment: VMSegment) -> String {
        guard memory.totalBytes > 0 else { return "—" }
        return (Double(segment.bytes) / Double(memory.totalBytes)).precisePercentLabel
    }

    // MARK: - Verdict

    private var verdict: some View {
        HStack(alignment: .top, spacing: 22) {
            reading(
                "Utilisation",
                value: memory.usedFraction.percentLabel,
                note: "app + wired + compressed",
                tint: tint(for: memory.utilisationBand)
            )
            reading(
                "Kernel pressure",
                value: memory.pressure.rawValue,
                note: "kern.memorystatus_vm_pressure_level",
                tint: tint(for: memory.pressure)
            )
            reading(
                "Swap",
                value: memory.swap.isActive ? memory.swap.usedBytes.byteLabel : "unused",
                note: memory.swap.isActive
                    ? "of \(memory.swap.totalBytes.byteLabel) · the compressor was not enough"
                    : "the compressor is absorbing everything",
                tint: memory.swap.isActive ? Theme.amber : Theme.green
            )
            Spacer(minLength: 0)
        }
    }

    private func reading(_ title: String, value: String, note: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.metricCaption)
                .foregroundStyle(Theme.inkSecondary)
                .textCase(.uppercase)
                .kerning(1)
            Text(value)
                .font(.metricFigure(16))
                .foregroundStyle(tint)
            Text(note)
                .font(.metricCaption)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tint(for pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: Theme.green
        case .warning: Theme.amber
        case .critical: Theme.ember
        }
    }

    private var accessibilitySummary: String {
        memory.composition
            .filter { $0.bytes > 0 }
            .map { "\($0.state.title) \($0.bytes.byteLabel)" }
            .joined(separator: ", ")
    }
}

extension VMPageState {
    var tint: Color {
        switch self {
        case .wired: Color(red: 0.937, green: 0.396, blue: 0.451)
        case .active: Color(red: 0.376, green: 0.706, blue: 0.996)
        case .inactive: Color(red: 0.435, green: 0.518, blue: 0.694)
        case .speculative: Color(red: 0.353, green: 0.796, blue: 0.812)
        case .compressed: Color(red: 0.663, green: 0.573, blue: 0.988)
        case .free: Color(red: 0.259, green: 0.855, blue: 0.545)
        case .unaccounted: Color(red: 0.278, green: 0.302, blue: 0.349)
        }
    }
}

#Preview {
    VMCompositionView(memory: MemoryMetrics(
        totalBytes: 8_589_934_592,
        appBytes: 1_975_000_000,
        wiredBytes: 2_109_000_000,
        compressedBytes: 2_818_000_000,
        freeBytes: 346_000_000,
        activeBytes: 1_513_000_000,
        inactiveBytes: 1_215_000_000,
        speculativeBytes: 287_000_000,
        fileBackedBytes: 1_040_000_000,
        swap: SwapUsage(totalBytes: 3_221_225_472, usedBytes: 1_100_000_000),
        pressure: .warning
    ))
    .padding(18)
    .frame(width: 720)
    .background(LoadWash(load: .elevated))
}
