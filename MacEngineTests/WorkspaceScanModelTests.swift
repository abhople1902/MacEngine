//
//  WorkspaceScanModelTests.swift
//  MacEngineTests
//

import XCTest
@testable import MacEngine

final class WorkspaceScanModelTests: XCTestCase {
    private func section(
        _ category: ScanCategory,
        bytes: UInt64,
        reclaimable: Bool
    ) -> ScanSection {
        ScanSection(
            category: category,
            node: DiskUsageNode(name: category.rawValue, path: "/tmp/\(category.rawValue)", byteCount: bytes, fileCount: 1),
            note: "",
            isReclaimable: reclaimable,
            isAbsent: false
        )
    }

    private func scan(_ sections: [ScanSection]) -> WorkspaceScan {
        WorkspaceScan(
            workspacePath: "/Projects/App/App.xcodeproj",
            workspaceName: "App",
            derivedDataPath: nil,
            sections: sections,
            toolchain: .empty,
            startedAt: Date(),
            duration: 1
        )
    }

    func testTotalIsEverySection() {
        let result = scan([
            section(.project, bytes: 100, reclaimable: false),
            section(.sharedCache, bytes: 900, reclaimable: true),
        ])
        XCTAssertEqual(result.totalBytes, 1_000)
    }

    func testReclaimableExcludesWhatYouCannotSafelyDelete() {
        let result = scan([
            section(.project, bytes: 100, reclaimable: false),
            section(.sharedCache, bytes: 900, reclaimable: true),
        ])
        XCTAssertEqual(result.reclaimableBytes, 900)
    }

    func testScanUpdateSurvivesTheJSONRoundTripUsedByXPC() throws {
        // An enum with associated values is the part of the wire format most
        // likely to break silently, so it is the part with a test.
        let original = ScanUpdate.progress(location: "ModuleCache.noindex", completed: 3, total: 14)
        let decoded = try JSONDecoder().decode(
            ScanUpdate.self,
            from: try JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded, original)
    }

    func testFinishedUpdateCarriesTheWholeScanAcrossJSON() throws {
        let original = ScanUpdate.finished(scan([section(.derivedData, bytes: 4_096, reclaimable: true)]))
        let decoded = try JSONDecoder().decode(
            ScanUpdate.self,
            from: try JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded, original)
    }

    func testNodeIdentityIsThePathSoRowsSurviveARescan() {
        let first = DiskUsageNode(name: "ModuleCache", path: "/x/ModuleCache", byteCount: 1, fileCount: 1)
        let second = DiskUsageNode(name: "ModuleCache", path: "/x/ModuleCache", byteCount: 999, fileCount: 9)
        XCTAssertEqual(first.id, second.id)
    }
}
