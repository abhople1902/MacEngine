import SwiftUI

struct StatusPillView: View {
    let state: DashboardViewModel.ConnectionState
    let source: MetricsSource

    private var tint: Color {
        switch state {
        case .streaming: Theme.green
        case .connecting, .recovering: Theme.amber
        case .failed: Theme.ember
        case .idle: Theme.inkTertiary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                    .shadow(color: tint.opacity(0.8), radius: 4)
                Text(state.label)
                    .font(.engineBody)
                    .foregroundStyle(Theme.ink)
            }

            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1, height: 12)

            Text(source.displayName)
                .font(.metricCaption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.surface.opacity(0.72), in: .capsule)
        .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: 1) }
        .help(state.detail ?? source.displayName)
    }
}
