//
//  DiagnosticsView.swift
//  MacEngine
//
//  The developer panel from the build plan. Killing the monitoring service is
//  the demo the whole architecture exists to support, so it gets a button
//  rather than a note in the README.
//

import SwiftUI

struct DiagnosticsView: View {
    @Bindable var model: DashboardViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                indicator(
                    "Metrics source",
                    value: model.source.displayName,
                    isHealthy: model.source.isolatesFailure
                )
                indicator(
                    "Connection",
                    value: model.connectionState.detail ?? model.connectionState.label,
                    isHealthy: model.connectionState.isStreaming
                )
                indicator(
                    "Snapshots received",
                    value: String(model.samplesTaken),
                    isHealthy: model.samplesTaken > 0
                )
            }

            Spacer()

            if model.canSimulateCrash {
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Kill Monitoring", systemImage: "bolt.trianglebadge.exclamationmark") {
                        model.simulateServiceCrash()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!model.connectionState.isStreaming)

                    Text("Terminates the service process")
                        .font(.metricCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func indicator(_ title: String, value: String, isHealthy: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isHealthy ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.metricCaption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.diagnosticMono)
        }
    }
}
