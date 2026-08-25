//
//  DiagnosticReport.swift
//  Shared
//
//  The text the diagnostic socket speaks.
//
//  Kept separate from the socket itself on purpose. The transport needs a live
//  service and a filesystem path to test; the wording needs neither, so it
//  lives here as a pure function over values and is covered by ordinary unit
//  tests. The socket is then only responsible for moving bytes.
//

import Foundation

/// The verbs the diagnostic socket understands. One request, one reply, one
/// connection — deliberately the simplest thing that a shell script or `nc`
/// can drive without a client library.
nonisolated enum DiagnosticVerb: String, CaseIterable {
    case status
    case snapshot
    case help

    var summary: String {
        switch self {
        case .status:   "Human-readable service and machine state"
        case .snapshot: "The latest MetricSnapshot as JSON"
        case .help:     "This list"
        }
    }
}

nonisolated enum DiagnosticReport {
    /// Strict request/response: the server never speaks first. A server that
    /// greets you means every client has to know to discard the greeting, and
    /// an empty request already returns the verb list, so `nc -U <path>` plus
    /// Return is discoverable enough.
    static func help() -> String {
        DiagnosticVerb.allCases
            .map { "  \($0.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0))\($0.summary)" }
            .joined(separator: "\n")
    }

    static func unknown(_ verb: String) -> String {
        "unknown verb \"\(verb)\"\n\nverbs:\n\(help())"
    }

    /// The `status` reply. Two blocks: what the service is doing, and what it
    /// last saw. A snapshot may legitimately be absent — the service starts
    /// sampling only when a client asks it to.
    static func status(info: ServiceInfo, snapshot: MetricSnapshot?, now: Date = Date()) -> String {
        var lines: [String] = ["macengine"]

        lines.append(row("service pid", "\(info.processIdentifier)"))
        lines.append(row("uptime", duration(now.timeIntervalSince(info.startedAt))))
        lines.append(row("monitoring", info.isMonitoring ? "yes" : "no"))
        lines.append(row("samples", "\(info.samplesTaken)"))
        lines.append(row("interval", String(format: "%.1fs", info.sampleInterval)))

        guard let snapshot else {
            lines.append("")
            lines.append("no snapshot yet — nothing has asked the service to start sampling")
            return lines.joined(separator: "\n")
        }

        lines.append("")
        lines.append(row("cpu", "\(percent(snapshot.cpu.busyFraction)) busy across \(snapshot.cpu.coreCount) cores"))
        lines.append(row("memory", "\(bytes(snapshot.memory.usedBytes)) of \(bytes(snapshot.memory.totalBytes))"
            + "  (\(percent(snapshot.memory.usedFraction)), pressure \(snapshot.memory.pressure.rawValue))"))

        if snapshot.memory.swap.isActive {
            lines.append(row("swap", "\(bytes(snapshot.memory.swap.usedBytes)) of \(bytes(snapshot.memory.swap.totalBytes))"))
        }

        lines.append(row("disk", "\(percent(snapshot.disk.usedFraction)) used on \(snapshot.disk.volumeName)"))
        lines.append(row("sampled", stamp(snapshot.timestamp)))

        if let top = snapshot.topProcesses.first {
            lines.append("")
            lines.append(row("top process", "\(top.name) (pid \(top.pid)) — \(percent(top.cpuFraction)) cpu"))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Formatting

    private static let labelWidth = 14

    private static func row(_ label: String, _ value: String) -> String {
        label.padding(toLength: labelWidth, withPad: " ", startingAt: 0) + value
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", (fraction * 100).rounded(toPlaces: 1))
    }

    /// Decimal units, matching what the rest of the app and Finder report.
    static func bytes(_ count: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(count)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        return unit == 0
            ? "\(count) B"
            : String(format: "%.2f %@", value, units[unit])
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(Swift.max(seconds, 0))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
