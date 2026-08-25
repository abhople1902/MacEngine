import OSLog

nonisolated enum Log {
    private static let subsystem = "com.AyushBhople.MacEngine"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let metrics = Logger(subsystem: subsystem, category: "metrics")
    static let xpc = Logger(subsystem: subsystem, category: "xpc")
    static let events = Logger(subsystem: subsystem, category: "events")
}
