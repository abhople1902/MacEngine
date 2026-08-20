//
//  DiskWalker.swift
//  Shared
//
//  Measures what a directory actually costs on disk.
//
//  Two deliberate choices worth defending. First, allocated size rather than
//  file size: a tree of ten thousand small files occupies far more than the sum
//  of its bytes, and the question being answered is "how much disk will I get
//  back", not "how much data is there". Second, the top level is walked
//  concurrently with a bounded task group while each subtree is walked
//  sequentially — the work is I/O bound on metadata, so a handful of parallel
//  walkers helps and thirty would only thrash.
//

import OSLog
import Foundation

nonisolated enum DiskWalker {
    /// Parallel walkers over top-level children. Chosen to be measured in
    /// block G rather than asserted here.
    static let defaultConcurrency = 4

    nonisolated struct Measurement: Sendable {
        var bytes: UInt64 = 0
        var files: Int = 0

        static func + (lhs: Measurement, rhs: Measurement) -> Measurement {
            Measurement(bytes: lhs.bytes + rhs.bytes, files: lhs.files + rhs.files)
        }
    }

    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
    ]

    /// How many entries to process between yielding the thread back.
    private static let checkpointInterval = 512

    /// Everything below `url`, walked sequentially. Returns zero for a path that
    /// does not exist, which is the normal case for Archives on a fresh machine.
    ///
    /// Async purely so it can yield. The loop itself is synchronous filesystem
    /// work, and several of them run at once — without handing the cooperative
    /// pool back periodically they occupy every thread in it and starve
    /// everything else in the process, including the task carrying the user's
    /// cancel request. Checking `Task.isCancelled` alone is not enough: the
    /// cancel has to be able to reach the actor in the first place.
    static func measure(_ url: URL) async -> Measurement {
        guard FileManager.default.fileExists(atPath: url.path) else { return Measurement() }

        // Hidden files and package contents are included on purpose: .noindex
        // caches and the insides of .app bundles are exactly what this is for.
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { failedURL, error in
                Log.metrics.debug("Skipped \(failedURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return true // one unreadable directory must not abort the walk
            }
        ) else {
            return Measurement()
        }

        var total = Measurement()
        var sinceCheckpoint = 0

        for case let fileURL as URL in enumerator {
            // Checking every iteration would cost more than the work itself.
            sinceCheckpoint += 1
            if sinceCheckpoint >= checkpointInterval {
                sinceCheckpoint = 0
                if Task.isCancelled { return total }
                await Task.yield()
            }

            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }

            // totalFileAllocatedSize includes metadata and any resource fork;
            // fileAllocatedSize is the fallback when it is unavailable.
            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            total.bytes += UInt64(max(size, 0))
            total.files += 1
        }

        return total
    }

    /// One level of children, each measured concurrently, rolled up into a node.
    /// Children are returned largest first because that is the only order anyone
    /// reads a disk breakdown in.
    static func scan(
        _ root: URL,
        name: String? = nil,
        concurrency: Int = defaultConcurrency,
        onChildFinished: (@Sendable (String) -> Void)? = nil
    ) async -> DiskUsageNode {
        let displayName = name ?? root.lastPathComponent

        guard FileManager.default.fileExists(atPath: root.path) else {
            return DiskUsageNode(name: displayName, path: root.path, byteCount: 0, fileCount: 0)
        }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []

        // A leaf, or a directory we could not list: measure it as one unit.
        guard !children.isEmpty else {
            let measured = await measure(root)
            return DiskUsageNode(
                name: displayName,
                path: root.path,
                byteCount: measured.bytes,
                fileCount: measured.files
            )
        }

        var nodes: [DiskUsageNode] = []
        nodes.reserveCapacity(children.count)

        await withTaskGroup(of: DiskUsageNode.self) { group in
            var next = 0
            let limit = Swift.max(1, concurrency)

            func addTask(_ url: URL) {
                group.addTask {
                    let measured = await measure(url)
                    onChildFinished?(url.lastPathComponent)
                    return DiskUsageNode(
                        name: url.lastPathComponent,
                        path: url.path,
                        byteCount: measured.bytes,
                        fileCount: measured.files
                    )
                }
            }

            // Prime the group, then keep exactly `limit` walkers in flight.
            while next < children.count, next < limit {
                addTask(children[next])
                next += 1
            }

            while let finished = await group.next() {
                nodes.append(finished)
                if next < children.count {
                    addTask(children[next])
                    next += 1
                }
            }
        }

        nodes.sort { $0.byteCount > $1.byteCount }

        return DiskUsageNode(
            name: displayName,
            path: root.path,
            byteCount: nodes.reduce(0) { $0 + $1.byteCount },
            fileCount: nodes.reduce(0) { $0 + $1.fileCount },
            children: nodes
        )
    }
}
