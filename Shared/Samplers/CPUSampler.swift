import OSLog
import Darwin
import Foundation

nonisolated final class CPUSampler {
    private var previous: host_cpu_load_info?
    private let coreCount = ProcessInfo.processInfo.processorCount

    func sample() -> CPUMetrics {
        guard let ticks = Self.hostCPULoad() else {
            Log.metrics.error("host_statistics(HOST_CPU_LOAD_INFO) failed")
            return .zero
        }
        defer { previous = ticks }

        guard let baseline = previous else {
            return CPUMetrics(
                userFraction: 0,
                systemFraction: 0,
                niceFraction: 0,
                idleFraction: 1,
                coreCount: coreCount
            )
        }

        // &- : the kernel's tick counters wrap, and a wrapped delta beats a trap.
        let user = Double(ticks.cpu_ticks.0 &- baseline.cpu_ticks.0)
        let system = Double(ticks.cpu_ticks.1 &- baseline.cpu_ticks.1)
        let idle = Double(ticks.cpu_ticks.2 &- baseline.cpu_ticks.2)
        let nice = Double(ticks.cpu_ticks.3 &- baseline.cpu_ticks.3)
        let total = user + system + idle + nice

        guard total > 0 else {
            return CPUMetrics(
                userFraction: 0,
                systemFraction: 0,
                niceFraction: 0,
                idleFraction: 1,
                coreCount: coreCount
            )
        }

        return CPUMetrics(
            userFraction: user / total,
            systemFraction: system / total,
            niceFraction: nice / total,
            idleFraction: idle / total,
            coreCount: coreCount
        )
    }

    func reset() {
        previous = nil
    }

    private static func hostCPULoad() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(
                    mach_host_self(),
                    host_flavor_t(HOST_CPU_LOAD_INFO),
                    rebound,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }
}
