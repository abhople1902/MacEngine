//
//  MonitoringEvent.swift
//  Shared
//
//  Lifecycle events broadcast over DistributedNotificationCenter. These are
//  deliberately *not* sent over XPC: they are low-rate, one-to-many, and must
//  still arrive when the XPC connection is exactly what has gone wrong.
//

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

/// A received lifecycle event, timestamped for the diagnostics log.
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
