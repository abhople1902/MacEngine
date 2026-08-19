//
//  CPUHistoryChart.swift
//  MacEngine
//
//  Swift Charts — part of the SDK, so the history view costs no dependency.
//

import Charts
import SwiftUI

struct CPUHistoryChart: View {
    let snapshots: [MetricSnapshot]
    var capacity: Int

    private var domain: ClosedRange<Date> {
        let now = snapshots.last?.timestamp ?? Date()
        let earliest = snapshots.first?.timestamp ?? now.addingTimeInterval(-1)
        return earliest...max(now, earliest.addingTimeInterval(1))
    }

    var body: some View {
        Chart(snapshots) { snapshot in
            AreaMark(
                x: .value("Time", snapshot.timestamp),
                y: .value("CPU", snapshot.cpu.busyFraction)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [.blue.opacity(0.35), .blue.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Time", snapshot.timestamp),
                y: .value("CPU", snapshot.cpu.busyFraction)
            )
            .foregroundStyle(.blue)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...1)
        .chartXScale(domain: domain)
        .chartYAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let fraction = value.as(Double.self) {
                        Text(fraction.percentLabel).font(.metricCaption)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.hour().minute().second(), collisionResolution: .greedy)
            }
        }
        .frame(height: 150)
        .overlay {
            if snapshots.isEmpty {
                Text("Waiting for the first sample")
                    .font(.metricCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("CPU usage over the last \(capacity) samples")
    }
}
