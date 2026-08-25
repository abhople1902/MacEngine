import Foundation

nonisolated struct DeveloperLocation: Sendable {
    let name: String
    let url: URL
    let category: ScanCategory
    let note: String
    let isReclaimable: Bool
}

nonisolated enum DeveloperFolders {
    static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static var developer: URL {
        home.appending(path: "Library/Developer", directoryHint: .isDirectory)
    }

    static var xcode: URL {
        developer.appending(path: "Xcode", directoryHint: .isDirectory)
    }

    static var derivedDataRoot: URL {
        xcode.appending(path: "DerivedData", directoryHint: .isDirectory)
    }

    static var swiftPMCache: URL {
        home.appending(path: "Library/Caches/org.swift.swiftpm", directoryHint: .isDirectory)
    }

    static func locations(
        projectDirectory: URL,
        derivedData: URL?
    ) -> [DeveloperLocation] {
        var result: [DeveloperLocation] = [
            DeveloperLocation(
                name: projectDirectory.lastPathComponent,
                url: projectDirectory,
                category: .project,
                note: "Your source, and anything you keep beside it.",
                isReclaimable: false
            )
        ]

        if let derivedData {
            result.append(DeveloperLocation(
                name: derivedData.lastPathComponent,
                url: derivedData,
                category: .derivedData,
                note: "Build products, the index store and build logs for this workspace. Rebuilt on demand.",
                isReclaimable: true
            ))
        }

        result += [
            DeveloperLocation(
                name: "ModuleCache.noindex",
                url: derivedDataRoot.appending(path: "ModuleCache.noindex", directoryHint: .isDirectory),
                category: .sharedCache,
                note: "Precompiled modules shared by every project. Usually the largest single cache, and the first thing to delete.",
                isReclaimable: true
            ),
            DeveloperLocation(
                name: "SymbolCache.noindex",
                url: derivedDataRoot.appending(path: "SymbolCache.noindex", directoryHint: .isDirectory),
                category: .sharedCache,
                note: "Shared symbol data for debugging.",
                isReclaimable: true
            ),
            DeveloperLocation(
                name: "SDKStatCaches.noindex",
                url: derivedDataRoot.appending(path: "SDKStatCaches.noindex", directoryHint: .isDirectory),
                category: .sharedCache,
                note: "Filesystem stat caches for each SDK, to save the compiler re-walking them.",
                isReclaimable: true
            ),
            DeveloperLocation(
                name: "CompilationCache.noindex",
                url: derivedDataRoot.appending(path: "CompilationCache.noindex", directoryHint: .isDirectory),
                category: .sharedCache,
                note: "Cached compilation results.",
                isReclaimable: true
            ),
            DeveloperLocation(
                name: "DocumentationCache",
                url: xcode.appending(path: "DocumentationCache", directoryHint: .isDirectory),
                category: .sharedCache,
                note: "Downloaded documentation. Re-fetched over the network, not rebuilt.",
                isReclaimable: true
            ),
            DeveloperLocation(
                name: "UserData",
                url: xcode.appending(path: "UserData", directoryHint: .isDirectory),
                category: .sharedCache,
                note: "Previews, snapshots, key bindings and code snippets. Grows quietly — but deleting it takes your editor settings with it.",
                isReclaimable: false
            ),
            DeveloperLocation(
                name: "Products",
                url: xcode.appending(path: "Products", directoryHint: .isDirectory),
                category: .sharedCache,
                note: "Built products kept outside DerivedData.",
                isReclaimable: true
            ),
            DeveloperLocation(
                name: "CoreSimulator/Devices",
                url: developer.appending(path: "CoreSimulator/Devices", directoryHint: .isDirectory),
                category: .simulator,
                note: "Every simulator you have ever booted, with its whole filesystem. Usually the biggest number here.",
                isReclaimable: true
            ),
            DeveloperLocation(
                name: "iOS DeviceSupport",
                url: xcode.appending(path: "iOS DeviceSupport", directoryHint: .isDirectory),
                category: .deviceSupport,
                note: "Symbols copied off each physical device, per OS build. Empty here; enormous on a machine that debugs devices.",
                isReclaimable: true
            ),
            DeveloperLocation(
                name: "watchOS DeviceSupport",
                url: xcode.appending(path: "watchOS DeviceSupport", directoryHint: .isDirectory),
                category: .deviceSupport,
                note: "As above, for watches.",
                isReclaimable: true
            ),
            DeveloperLocation(
                name: "Archives",
                url: xcode.appending(path: "Archives", directoryHint: .isDirectory),
                category: .archives,
                note: "Every build you ever archived, with its dSYMs. Empty here — and the one people are most surprised by.",
                isReclaimable: false
            ),
            DeveloperLocation(
                name: "Packages",
                url: developer.appending(path: "Packages", directoryHint: .isDirectory),
                category: .packages,
                note: "Swift package checkouts shared across projects.",
                isReclaimable: true
            ),
            DeveloperLocation(
                name: "org.swift.swiftpm",
                url: swiftPMCache,
                category: .packages,
                note: "SwiftPM's resolved package cache.",
                isReclaimable: true
            ),
        ]

        return result
    }
}

nonisolated enum WorkspaceLocator {
    static func derivedData(
        forWorkspaceAt workspace: URL,
        in root: URL = DeveloperFolders.derivedDataRoot
    ) -> URL? {
        let wanted = workspace.standardizedFileURL.resolvingSymlinksInPath().path

        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for candidate in candidates {
            let plist = candidate.appending(path: "info.plist", directoryHint: .notDirectory)
            guard let data = try? Data(contentsOf: plist),
                  let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dictionary = parsed as? [String: Any],
                  let recorded = dictionary["WorkspacePath"] as? String
            else { continue }

            let resolved = URL(fileURLWithPath: recorded).standardizedFileURL.resolvingSymlinksInPath().path
            if resolved == wanted { return candidate }
        }

        return nil
    }
}
