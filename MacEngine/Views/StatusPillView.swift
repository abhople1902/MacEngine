//
//  StatusPillView.swift
//  MacEngine
//

import SwiftUI

struct StatusPillView: View {
    let state: DashboardViewModel.ConnectionState
    let source: MetricsSource

    private var tint: Color {
        switch state {
        case .streaming: .green
        case .connecting, .recovering: .orange
        case .failed: .red
        case .idle: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(state.label)
                    .font(.system(.callout, weight: .medium))
            }

            Divider().frame(height: 12)

            Text(source.displayName)
                .font(.metricCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.background.secondary, in: .capsule)
        .overlay { Capsule().strokeBorder(.separator, lineWidth: 0.5) }
        .help(state.detail ?? source.displayName)
    }
}
