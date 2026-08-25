import Foundation

nonisolated struct ProcessSample: Codable, Sendable, Equatable, Identifiable {
    let pid: Int32
    let name: String
    let cpuFraction: Double
    let memoryBytes: UInt64

    var id: Int32 { pid }
}
