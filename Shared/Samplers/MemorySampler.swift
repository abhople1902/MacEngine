//
//  MemorySampler.swift
//  MacEngine
//
//  Reads the Mach VM statistics and folds them into the same three buckets
//  Activity Monitor reports: app memory, wired memory and compressed memory.
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
            freeBytes: UInt64(stats.free_count) * pageSize
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
}
