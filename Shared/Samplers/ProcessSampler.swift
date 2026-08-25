import OSLog
import Darwin
import Foundation

nonisolated final class ProcessSampler {
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
        nameCache = nameCache.filter { currentCPUTime.keys.contains($0.key) }

        return heaviest.sortedDescending()
    }

    func reset() {
        previousCPUTime.removeAll()
        lastSampledAt = nil
    }

    func toolchainFootprint(now: Date = Date()) -> ToolchainFootprint {
        let elapsedNanoseconds = lastSampledAt
            .map { Swift.max(now.timeIntervalSince($0), 0) * 1_000_000_000 } ?? 0

        var grouped: [String: (count: Int, bytes: UInt64, cpu: Double)] = [:]

        for pid in Self.livePIDs() {
            let executable = name(for: pid)
            guard Self.isToolchain(executable) else { continue }
            guard let task = Self.taskInfo(for: pid) else { continue }

            var cpuFraction = 0.0
            let cpuTime = task.pti_total_user &+ task.pti_total_system
            if elapsedNanoseconds > 0, let baseline = previousCPUTime[pid], cpuTime > baseline {
                cpuFraction = Double(cpuTime - baseline) / elapsedNanoseconds
            }

            var entry = grouped[executable] ?? (0, 0, 0)
            entry.count += 1
            entry.bytes += task.pti_resident_size
            entry.cpu += cpuFraction
            grouped[executable] = entry
        }

        let groups = grouped
            .map { ToolchainGroup(name: $0.key, processCount: $0.value.count, memoryBytes: $0.value.bytes, cpuFraction: $0.value.cpu) }
            .sorted { $0.memoryBytes > $1.memoryBytes }

        return ToolchainFootprint(groups: groups)
    }

    private static let toolchainNames: Set<String> = [
        "Xcode", "xcodebuild", "XCBBuildService", "SourceKitService",
        "swift-frontend", "swift-driver", "swift", "swiftc",
        "clang", "clangd", "ld", "ld-prime", "libtool", "dsymutil",
        "lldb", "debugserver", "lldb-rpc-server",
        "Simulator", "CoreSimulatorService", "SimulatorTrampoline", "launchd_sim",
        "IBAgent-macOS", "IBCocoaTouchImageCatalogTool", "actool", "ibtool",
        "MTLCompilerService", "Instruments", "InstrumentsDeviceService",
    ]

    private static let toolchainPrefixes = [
        "swift-", "com.apple.CoreSimulator", "XCTest", "MTLCompiler", "AssetCatalog",
    ]

    private static func isToolchain(_ executable: String) -> Bool {
        if toolchainNames.contains(executable) { return true }
        return toolchainPrefixes.contains { executable.hasPrefix($0) }
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

        // Headroom: the table can grow between the sizing call and the read,
        // and proc_listallpids truncates silently rather than failing.
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
        return written == size ? info : nil
    }

    private static let pathBufferSize = 4 * Int(MAXPATHLEN)

    private static func executableName(for pid: Int32) -> String {
        var pathBuffer = [CChar](repeating: 0, count: pathBufferSize)
        if proc_pidpath(pid, &pathBuffer, UInt32(pathBufferSize)) > 0 {
            let path = String(cString: pathBuffer)
            if !path.isEmpty {
                return (path as NSString).lastPathComponent
            }
        }

        var nameBuffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        if proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 {
            let name = String(cString: nameBuffer)
            if !name.isEmpty { return name }
        }

        return "pid \(pid)"
    }
}
