import Charts
import SwiftUI

nonisolated enum ChartWindow {
    static let length: TimeInterval = 60

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
