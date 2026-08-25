import Foundation

nonisolated enum MonitoringEvent: String, CaseIterable, Sendable {
    case monitoringStarted = "com.AyushBhople.MacEngine.event.monitoringStarted"
    case monitoringStopped = "com.AyushBhople.MacEngine.event.monitoringStopped"
    case serviceUnavailable = "com.AyushBhople.MacEngine.event.serviceUnavailable"
    case serviceRecovered = "com.AyushBhople.MacEngine.event.serviceRecovered"
    case highCPUDetected = "com.AyushBhople.MacEngine.event.highCPUDetected"

    var notificationName: Notification.Name { Notification.Name(rawValue) }

    var displayName: String {
        switch self {
        case .monitoringStarted: "Monitoring started"
        case .monitoringStopped: "Monitoring stopped"
        case .serviceUnavailable: "Monitoring service unavailable"
        case .serviceRecovered: "Monitoring service recovered"
        case .highCPUDetected: "High CPU detected"
        }
    }
}

nonisolated struct MonitoringEventRecord: Identifiable, Sendable, Equatable {
    let id = UUID()
    let event: MonitoringEvent
    let timestamp: Date
    let detail: String?

    init(event: MonitoringEvent, timestamp: Date = Date(), detail: String? = nil) {
        self.event = event
        self.timestamp = timestamp
        self.detail = detail
    }
}
