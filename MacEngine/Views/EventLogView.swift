import SwiftUI

struct EventLogView: View {
    let records: [MonitoringEventRecord]
    var limit: Int = 6

    var body: some View {
        if records.isEmpty {
            Text("No lifecycle events yet.")
                .font(.metricCaption)
                .foregroundStyle(Theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(records.prefix(limit)) { record in
                    HStack(spacing: 10) {
                        Image(systemName: record.event.symbolName)
                            .foregroundStyle(record.event.tint)
                            .frame(width: 16)
                        Text(record.event.displayName)
                            .font(.metricCaption)
                        if let detail = record.detail {
                            Text(detail)
                                .font(.diagnosticMono)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                        Text(record.timestamp, format: .dateTime.hour().minute().second())
                            .font(.diagnosticMono)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .padding(.vertical, 5)
                    if record.id != records.prefix(limit).last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

extension MonitoringEvent {
    var symbolName: String {
        switch self {
        case .monitoringStarted: "play.circle"
        case .monitoringStopped: "stop.circle"
        case .serviceUnavailable: "exclamationmark.triangle"
        case .serviceRecovered: "arrow.clockwise.circle"
        case .highCPUDetected: "flame"
        }
    }

    var tint: Color {
        switch self {
        case .monitoringStarted, .serviceRecovered: Theme.green
        case .monitoringStopped: Theme.inkTertiary
        case .serviceUnavailable: Theme.ember
        case .highCPUDetected: Theme.amber
        }
    }
}
