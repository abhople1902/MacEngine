//
//  Log.swift
//  Shared
//
//  One os.Logger per subsystem area. Using the unified log (rather than print)
//  means the app, the XPC service and the agent all stream into a single
//  `log stream --predicate 'subsystem == "com.AyushBhople.MacEngine"'` session.
//

import OSLog

nonisolated enum Log {
    private static let subsystem = "com.AyushBhople.MacEngine"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let metrics = Logger(subsystem: subsystem, category: "metrics")
    static let xpc = Logger(subsystem: subsystem, category: "xpc")
    static let events = Logger(subsystem: subsystem, category: "events")
}
