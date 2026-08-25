//
//  DiskWalker.swift
//  Shared
//
//  Measures what a directory actually costs on disk.
//
//  Three deliberate choices worth defending. First, allocated size rather than
//  file size: a tree of ten thousand small files occupies far more than the sum
//  of its bytes, and the question being answered is "how much disk will I get
//  back", not "how much data is there". Second, the top level is walked
//  concurrently with a bounded task group while each subtree is walked
//  sequentially — the work is I/O bound on metadata, so a handful of parallel
//  walkers helps and thirty would only thrash.
//
//  Third, the subtree walk is fts(3) rather than FileManager.enumerator. That
//  started as a guess and ended as a measurement: see Documentation/instruments.md.
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

    /// How many entries to process between yielding the thread back.
    private static let checkpointInterval = 512

    /// Everything below `url`, walked with fts(3). Returns zero for a path that
    /// does not exist, which is the normal case for Archives on a fresh machine.
    ///
    /// This was `FileManager.enumerator` plus `resourceValues(forKeys:)` until
    /// the Time Profiler was pointed at it. Foundation was not slow at reading
    /// the filesystem — `getattrlistbulk` was under one percent of the trace —
    /// it was slow at wrapping the results, allocating a CFURL and bridging an
    /// NSDictionary per file to extract a single integer. fts(3) hands back a
    /// `struct stat` directly and allocates nothing per entry.
    ///
    /// `st_blocks` is in 512-byte units by definition, and counts blocks the
    /// file actually occupies, which is the same question the old
    /// `totalFileAllocatedSize` was asking.
    ///
    /// Async purely so it can yield. The loop itself is synchronous filesystem
    /// work, and several of them run at once — without handing the cooperative
    /// pool back periodically they occupy every thread in it and starve
    /// everything else in the process, including the task carrying the user's
    /// cancel request. Checking `Task.isCancelled` alone is not enough: the
    /// cancel has to be able to reach the actor in the first place.
    static func measure(_ url: URL) async -> Measurement {
        guard FileManager.default.fileExists(atPath: url.path) else { return Measurement() }

        // fts mutates the array it is handed, so it cannot be a literal.
        guard let root = strdup(url.path) else { return Measurement() }
        defer { free(root) }
        var roots: [UnsafeMutablePointer<CChar>?] = [root, nil]

        // FTS_PHYSICAL keeps symlinks from being followed, matching what the
        // directory enumerator did. FTS_NOCHDIR is what makes this safe to
        // suspend: without it fts walks by changing the process working
        // directory, and this loop resumes on whatever thread it likes.
        // Hidden files and package contents are included on purpose: .noindex
        // caches and the insides of .app bundles are exactly what this is for.
        guard let stream = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            return Measurement()
        }
        defer { fts_close(stream) }

        var total = Measurement()
        var sinceCheckpoint = 0

        while let entry = fts_read(stream) {
            // Checking every iteration would cost more than the work itself.
            sinceCheckpoint += 1
            if sinceCheckpoint >= checkpointInterval {
                sinceCheckpoint = 0
                if Task.isCancelled { return total }
                await Task.yield()
            }

            switch Int32(entry.pointee.fts_info) {
            case FTS_F:
                guard let status = entry.pointee.fts_statp else { continue }
                total.bytes += UInt64(max(status.pointee.st_blocks, 0)) * 512
                total.files += 1

            // One unreadable directory must not abort the walk.
            case FTS_DNR, FTS_ERR, FTS_NS:
                let failed = entry.pointee.fts_path.map { String(cString: $0) } ?? "?"
                Log.metrics.debug("Skipped \(failed, privacy: .public): errno \(entry.pointee.fts_errno)")

            default:
                break
            }
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
