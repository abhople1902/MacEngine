//
//  CPUHistoryChart.swift
//  MacEngine
//
//  Swift Charts — part of the SDK, so the history view costs no dependency.
//
//  The x axis is a fixed-width window, not a fitted domain. For the first
//  minute the axis stands still and the trace grows into it from the left;
//  after that the window slides and the trace stays pinned to the right edge.
//  A domain fitted to the samples would rescale on every tick, which makes a
//  flat machine and a busy one look identical.
//

import Charts
import SwiftUI

/// The x-axis window, kept out of the view so it can be tested without one.
nonisolated enum ChartWindow {
    /// How much time the axis shows at once.
    static let length: TimeInterval = 60

    /// Anchored to `first` until a full window has elapsed, then sliding so the
    /// newest sample sits on the right edge. Either way the axis is exactly
    /// `length` wide, which is the point.
    static func domain(first: Date?, last: Date?, now: @autoclosure () -> Date = Date()) -> ClosedRange<Date> {
        guard let first else {
            let start = now()
            return start...start.addingTimeInterval(length)
        }

        let last = last ?? first
        guard last.timeIntervalSince(first) > length else {
            return first...first.addingTimeInterval(length)
        }
        return last.addingTimeInterval(-length)...last
    }
}

struct CPUHistoryChart: View {
    let snapshots: [MetricSnapshot]
    var capacity: Int
    var load: SystemLoad = .nominal

    private var domain: ClosedRange<Date> {
        ChartWindow.domain(first: snapshots.first?.timestamp, last: snapshots.last?.timestamp)
    }

    private var trace: Color { load == .nominal ? Theme.cpu : load.tint }

    var body: some View {
        Chart(snapshots) { snapshot in
            AreaMark(
                x: .value("Time", snapshot.timestamp),
                y: .value("CPU", snapshot.cpu.busyFraction)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [trace.opacity(0.42), trace.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Time", snapshot.timestamp),
                y: .value("CPU", snapshot.cpu.busyFraction)
            )
            .foregroundStyle(trace)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...1)
        .chartXScale(domain: domain)
        .chartPlotStyle { plot in
            plot.background(Theme.sunk, in: .rect(cornerRadius: 8))
        }
        .chartYAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let fraction = value.as(Double.self) {
                        Text(fraction.percentLabel)
                            .font(.metricCaption)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            // Fixed 15-second ticks: the window never changes width, so the
            // labels should not change count either.
            AxisMarks(values: .stride(by: .second, count: 15)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel(format: .dateTime.minute().second(), collisionResolution: .greedy)
                    .font(.metricCaption)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .animation(.linear(duration: 0.2), value: snapshots.count)
        .frame(height: 150)
        .overlay {
            if snapshots.isEmpty {
                Text("Waiting for the first sample")
                    .font(.metricCaption)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .accessibilityLabel("CPU usage over the last \(Int(ChartWindow.length)) seconds, \(capacity) samples held")
    }
}
