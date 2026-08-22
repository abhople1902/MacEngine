//
//  MemorySampler.swift
//  MacEngine
//
//  Reads the Mach VM statistics and folds them into the same three buckets
//  Activity Monitor reports: app memory, wired memory and compressed memory.
//  Engineer Mode wants the states underneath that summary, so the full page
//  composition, swap usage and the kernel's pressure level come back too.
//

import OSLog
import Darwin
import Foundation

nonisolated final class MemorySampler {
    private let totalBytes = ProcessInfo.processInfo.physicalMemory
    private let pageSize = UInt64(vm_kernel_page_size)

    func sample() -> MemoryMetrics {
        guard let stats = Self.vmStatistics() else {
            Log.metrics.error("host_statistics64(HOST_VM_INFO64) failed")
            return .zero
        }

        // App memory is anonymous pages minus the purgeable ones the system can
        // reclaim on demand; subtracting with saturation guards against the two
        // counters being read a hair apart.
        let anonymous = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let appPages = anonymous > purgeable ? anonymous - purgeable : 0

        return MemoryMetrics(
            totalBytes: totalBytes,
            appBytes: appPages * pageSize,
            wiredBytes: UInt64(stats.wire_count) * pageSize,
            compressedBytes: UInt64(stats.compressor_page_count) * pageSize,
            freeBytes: UInt64(stats.free_count) * pageSize,
            activeBytes: UInt64(stats.active_count) * pageSize,
            inactiveBytes: UInt64(stats.inactive_count) * pageSize,
            speculativeBytes: UInt64(stats.speculative_count) * pageSize,
            fileBackedBytes: UInt64(stats.external_page_count) * pageSize,
            swap: Self.swapUsage(),
            pressure: Self.pressureLevel()
        )
    }

    private static func vmStatistics() -> vm_statistics64_data_t? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(
                    mach_host_self(),
                    host_flavor_t(HOST_VM_INFO64),
                    rebound,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? stats : nil
    }

    /// `vm.swapusage` hands back an `xsw_usage` by value.
    private static func swapUsage() -> SwapUsage {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            Log.metrics.error("sysctl vm.swapusage failed")
            return .zero
        }
        return SwapUsage(totalBytes: usage.xsu_total, usedBytes: usage.xsu_used)
    }

    /// The kernel's verdict, which is a different question from "how full is
    /// the machine". `kern.memorystatus_vm_pressure_level` is a bitmask:
    /// 1 normal, 2 warning, 4 critical.
    private static func pressureLevel() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            Log.metrics.error("sysctl kern.memorystatus_vm_pressure_level failed")
            return .normal
        }
        return MemoryPressure(pressureLevel: level)
    }
}

nonisolated extension MemoryPressure {
    /// Anything the kernel has not told us about is reported as normal rather
    /// than guessed at — a wrong alarm is worse than no alarm.
    init(pressureLevel: Int32) {
        switch pressureLevel {
        case 4: self = .critical
        case 2: self = .warning
        default: self = .normal
        }
    }
}
