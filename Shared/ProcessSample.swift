//
//  ProcessSample.swift
//  Shared
//
//  One row of the "Top Processes" table. Populated by the monitoring service
//  in Block B; the app only ever renders what it is handed.
//

import Foundation

nonisolated struct ProcessSample: Codable, Sendable, Equatable, Identifiable {
    let pid: Int32
    let name: String
    /// Share of one core's time, 0...1 — may exceed 1 on multi-threaded work.
    let cpuFraction: Double
    let memoryBytes: UInt64

    var id: Int32 { pid }
}
