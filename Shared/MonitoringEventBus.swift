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

    static func payload(from notification: Notification) -> (detail: String?, senderPID: Int32)? {
        let info = notification.userInfo as? [String: String]
        let senderPID = info?[senderPIDKey].flatMap(Int32.init)
        guard let senderPID, senderPID != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return (info?[detailKey], senderPID)
    }
}
