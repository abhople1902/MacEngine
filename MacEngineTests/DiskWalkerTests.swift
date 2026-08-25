//
//  DiskWalkerTests.swift
//  MacEngineTests
//
//  Built against a real temporary tree rather than a mocked FileManager,
//  because the behaviour worth testing — allocated size, roll-up, ordering —
//  only exists on a real filesystem.
//

import XCTest
@testable import MacEngine

final class DiskWalkerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "DiskWalkerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func makeFile(_ relativePath: String, bytes: Int) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    func testMissingPathMeasuresZeroRatherThanFailing() async {
        let absent = root.appending(path: "does-not-exist")
        let measured = await DiskWalker.measure(absent)
        XCTAssertEqual(measured.bytes, 0)
        XCTAssertEqual(measured.files, 0)
    }

    func testEveryFileInTheTreeIsCounted() async throws {
        try makeFile("a.bin", bytes: 100)
        try makeFile("nested/b.bin", bytes: 100)
        try makeFile("nested/deeper/c.bin", bytes: 100)

        let measured = await DiskWalker.measure(root)
        XCTAssertEqual(measured.files, 3)
    }

    func testAllocatedSizeIsAtLeastTheLogicalSize() async throws {
        try makeFile("big.bin", bytes: 50_000)
        // Allocated size rounds up to whole blocks, so it can exceed the logical
        // size but must never be less.
        let measured = await DiskWalker.measure(root)
        XCTAssertGreaterThanOrEqual(measured.bytes, 50_000)
    }

    func testParentTotalIsTheSumOfItsChildren() async throws {
        try makeFile("one/a.bin", bytes: 10_000)
        try makeFile("two/b.bin", bytes: 20_000)
        try makeFile("three/c.bin", bytes: 30_000)

        let node = await DiskWalker.scan(root)
        let childSum = node.children.reduce(UInt64(0)) { $0 + $1.byteCount }

        XCTAssertEqual(node.byteCount, childSum)
        XCTAssertEqual(node.fileCount, 3)
    }

    func testChildrenComeBackLargestFirst() async throws {
        try makeFile("small/a.bin", bytes: 1_000)
        try makeFile("large/b.bin", bytes: 400_000)
        try makeFile("medium/c.bin", bytes: 90_000)

        let node = await DiskWalker.scan(root)
        XCTAssertEqual(node.children.map(\.name), ["large", "medium", "small"])
    }

    func testConcurrencyDoesNotChangeTheResult() async throws {
        // Sizes must differ by more than one allocation block, or they round
        // to identical allocated sizes and the ordering assertion below is
        // comparing ties — which sort() is free to break either way.
        for i in 0..<12 {
            try makeFile("dir\(i)/file.bin", bytes: (i + 1) * 40_000)
        }

        let serial = await DiskWalker.scan(root, concurrency: 1)
        let parallel = await DiskWalker.scan(root, concurrency: 8)

        XCTAssertEqual(serial.byteCount, parallel.byteCount)
        XCTAssertEqual(serial.children.map(\.name), parallel.children.map(\.name))
    }

    /// Regression: `scan` hands every top-level child to `measure`, and the old
    /// implementation opened a *directory* enumerator on each one — which
    /// yields nothing at all for a plain file. Every file sitting directly in a
    /// scanned folder was silently counted as zero. On this Mac that was 933
    /// files and 546 MB, most of it the top level of ModuleCache.noindex.
    func testFilesDirectlyInTheRootAreCounted() async throws {
        try makeFile("loose.bin", bytes: 30_000)
        try makeFile("nested/deep.bin", bytes: 30_000)

        let node = await DiskWalker.scan(root)
        XCTAssertEqual(node.fileCount, 2)
    }

    func testScanOfAMissingRootIsAnEmptyNode() async {
        let node = await DiskWalker.scan(root.appending(path: "nope"))
        XCTAssertEqual(node.byteCount, 0)
        XCTAssertTrue(node.children.isEmpty)
    }
}
