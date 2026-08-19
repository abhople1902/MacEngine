//
//  MonitoringEventBus.swift
//  Shared
//
//  Thin wrapper over DistributedNotificationCenter so every process posts the
//  same shape. Each notification carries the sender's pid, which lets a
//  receiver ignore the events it posted itself — the notification center
//  delivers back to the posting process too.
//

import Foundation

nonisolated enum MonitoringEventBus {
    static let detailKey = "detail"
    static let senderPIDKey = "senderPID"

    static func post(_ event: MonitoringEvent, detail: String? = nil) {
        var userInfo: [String: String] = [
            senderPIDKey: String(ProcessInfo.processInfo.processIdentifier)
        ]
        if let detail { userInfo[detailKey] = detail }

        DistributedNotificationCenter.default().postNotificationName(
            event.notificationName,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    /// `nil` when the notification came from this process and should be ignored.
    static func payload(from notification: Notification) -> (detail: String?, senderPID: Int32)? {
        let info = notification.userInfo as? [String: String]
        let senderPID = info?[senderPIDKey].flatMap(Int32.init)
        guard let senderPID, senderPID != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return (info?[detailKey], senderPID)
    }
}
