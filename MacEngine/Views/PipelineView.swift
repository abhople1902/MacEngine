import SwiftUI

struct PipelineView: View {
    let timing: PipelineTiming?

    var body: some View {
        if let timing, !timing.stages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                stages(timing)
                Divider().overlay(Theme.hairline)
                footer(timing)
            }
        } else {
            Text("The in-process provider has no boundary to cross, so there is no pipeline to measure.")
                .font(.metricCaption)
                .foregroundStyle(Theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        }
    }

    private func stages(_ timing: PipelineTiming) -> some View {
        let slowest = timing.stages.map(\.microseconds).max() ?? 1

        return VStack(alignment: .leading, spacing: 9) {
            ForEach(timing.stages) { stage in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(stage.name)
                            .font(.engineBody)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        Text(label(stage))
                            .font(.metricFigure(13))
                            .foregroundStyle(tint(stage))
                            .frame(width: 82, alignment: .trailing)
                    }

                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tint(stage))
                            .frame(width: max(proxy.size.width * (stage.microseconds / max(slowest, 1)), 2))
                    }
                    .frame(height: 5)

                    Text(stage.detail)
                        .font(.metricCaption)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
        }
    }

    private func footer(_ timing: PipelineTiming) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("KERNEL TO VIEW MODEL")
                    .font(.metricCaption)
                    .foregroundStyle(Theme.inkSecondary)
                    .kerning(1)
                Text(timing.total.map { format($0 * 1_000_000) } ?? "—")
                    .font(.metricFigure(16))
                    .foregroundStyle(Theme.ink)
            }

            Text("Wall clock, sampled in one process and finished in another — sound only because both read the same host clock. What SwiftUI does after the hand-off is Instruments' question, not this panel's.")
                .font(.metricCaption)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ stage: PipelineStage) -> String {
        format(stage.microseconds)
    }

    private func format(_ microseconds: Double) -> String {
        microseconds >= 1000
            ? "\((microseconds / 1000).formatted(.number.precision(.fractionLength(2)))) ms"
            : "\(microseconds.formatted(.number.precision(.fractionLength(0)))) µs"
    }

    private func tint(_ stage: PipelineStage) -> Color {
        switch stage.name {
        case "collect": Theme.amber
        case "encode + transit": Theme.cpu
        case "decode": Theme.memory
        default: Theme.disk
        }
    }
}
