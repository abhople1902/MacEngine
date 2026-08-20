//
//  ProcessSampler.swift
//  Shared
//
//  Enumerates live processes and returns the heaviest CPU consumers.
//
//  This is the sampler that justifies the whole multi-process design: it needs
//  to read task info for processes it does not own, which the App Sandbox
//  denies. Running it inside the monitoring service means the service can drop
//  the sandbox while the app keeps whatever restrictions it likes.
//
//  Like `CPUSampler`, per-process CPU time is a monotonic total, so usage only
//  exists between two readings.
//

import OSLog
import Darwin
import Foundation

nonisolated final class ProcessSampler {
    /// Executable paths are stable for a pid's lifetime, so they are resolved
    /// once and reused — `proc_pidpath` is by far the most expensive call here.
    private var nameCache: [Int32: String] = [:]
    private var previousCPUTime: [Int32: UInt64] = [:]
    private var lastSampledAt: Date?

    func sample(limit: Int = 5, now: Date = Date()) -> [ProcessSample] {
        let pids = Self.livePIDs()
        guard !pids.isEmpty else {
            Log.metrics.error("proc_listallpids returned nothing")
            return []
        }

        let elapsed = lastSampledAt.map { now.timeIntervalSince($0) } ?? 0
        let elapsedNanoseconds = elapsed > 0 ? elapsed * 1_000_000_000 : 0

        var currentCPUTime: [Int32: UInt64] = [:]
        currentCPUTime.reserveCapacity(pids.count)
        var heaviest = BoundedTopK<ProcessSample>(capacity: limit)

        for pid in pids {
            guard let task = Self.taskInfo(for: pid) else { continue }

            let cpuTime = task.pti_total_user &+ task.pti_total_system
            currentCPUTime[pid] = cpuTime

            // Without a baseline there is no interval to divide by, so the
            // first sample after launch reports memory only.
            var cpuFraction = 0.0
            if elapsedNanoseconds > 0, let baseline = previousCPUTime[pid], cpuTime > baseline {
                cpuFraction = Double(cpuTime - baseline) / elapsedNanoseconds
            }

            heaviest.insert(
                ProcessSample(
                    pid: pid,
                    name: name(for: pid),
                    cpuFraction: cpuFraction,
                    memoryBytes: task.pti_resident_size
                ),
                score: cpuFraction
            )
        }

        previousCPUTime = currentCPUTime
        lastSampledAt = now
        // Processes die constantly; without this the caches grow all day.
        nameCache = nameCache.filter { currentCPUTime.keys.contains($0.key) }

        return heaviest.sortedDescending()
    }

    func reset() {
        previousCPUTime.removeAll()
        lastSampledAt = nil
    }

    private func name(for pid: Int32) -> String {
        if let cached = nameCache[pid] { return cached }
        let resolved = Self.executableName(for: pid)
        nameCache[pid] = resolved
        return resolved
    }

    private static func livePIDs() -> [Int32] {
        let bytes = proc_listallpids(nil, 0)
        guard bytes > 0 else { return [] }

        // Ask for headroom: processes can spawn between the sizing call and the
        // read, and proc_listallpids silently truncates rather than failing.
        let capacity = Int(bytes) + 64
        var pids = [Int32](repeating: 0, count: capacity)
        let written = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(capacity * MemoryLayout<Int32>.size))
        }
        guard written > 0 else { return [] }

        return Array(pids.prefix(Int(written))).filter { $0 > 0 }
    }

    private static func taskInfo(for pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        // Short reads mean the process died mid-call, or is one we may not
        // inspect; either way it is skipped rather than reported as zero.
        return written == size ? info : nil
    }

    /// `PROC_PIDPATHINFO_MAXSIZE` is a C macro, so it does not reach Swift;
    /// this is the same `4 * MAXPATHLEN` the header defines it as.
    private static let pathBufferSize = 4 * Int(MAXPATHLEN)

    private static func executableName(for pid: Int32) -> String {
        var pathBuffer = [CChar](repeating: 0, count: pathBufferSize)
        if proc_pidpath(pid, &pathBuffer, UInt32(pathBufferSize)) > 0 {
            let path = String(cString: pathBuffer)
            if !path.isEmpty {
                return (path as NSString).lastPathComponent
            }
        }

        // proc_pidpath fails for some system processes; proc_name still works
        // but truncates to a short name.
        var nameBuffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        if proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 {
            let name = String(cString: nameBuffer)
            if !name.isEmpty { return name }
        }

        return "pid \(pid)"
    }
}
