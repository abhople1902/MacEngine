import OSLog
import Foundation

nonisolated enum DiskWalker {
    static let defaultConcurrency = 4

    nonisolated struct Measurement: Sendable {
        var bytes: UInt64 = 0
        var files: Int = 0

        static func + (lhs: Measurement, rhs: Measurement) -> Measurement {
            Measurement(bytes: lhs.bytes + rhs.bytes, files: lhs.files + rhs.files)
        }
    }

    private static let checkpointInterval = 512

    static func measure(_ url: URL) async -> Measurement {
        guard FileManager.default.fileExists(atPath: url.path) else { return Measurement() }

        guard let root = strdup(url.path) else { return Measurement() }
        defer { free(root) }
        var roots: [UnsafeMutablePointer<CChar>?] = [root, nil]

        // FTS_NOCHDIR is required: this loop suspends at Task.yield() and may
        // resume on another thread, and fts otherwise walks by chdir'ing.
        // Sizes are st_blocks * 512 — allocated, not logical.
        guard let stream = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            return Measurement()
        }
        defer { fts_close(stream) }

        var total = Measurement()
        var sinceCheckpoint = 0

        while let entry = fts_read(stream) {
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

            case FTS_DNR, FTS_ERR, FTS_NS:
                let failed = entry.pointee.fts_path.map { String(cString: $0) } ?? "?"
                Log.metrics.debug("Skipped \(failed, privacy: .public): errno \(entry.pointee.fts_errno)")

            default:
                break
            }
        }

        return total
    }

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
