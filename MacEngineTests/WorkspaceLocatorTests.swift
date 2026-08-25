import XCTest
@testable import MacEngine

final class WorkspaceLocatorTests: XCTestCase {
    private var derivedData: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        derivedData = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "DerivedData-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: derivedData, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: derivedData)
        try super.tearDownWithError()
    }

    private func makeFolder(named name: String, claiming workspacePath: String?) throws {
        let folder = derivedData.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let workspacePath else { return }

        let plist: [String: Any] = ["WorkspacePath": workspacePath, "LastAccessedDate": Date()]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: folder.appending(path: "info.plist", directoryHint: .notDirectory))
    }

    func testFolderIsFoundByTheWorkspaceItClaims() throws {
        try makeFolder(named: "Other-aaaaaaaaaaaaaaaaaaaaaaaaaaaa", claiming: "/Projects/Other/Other.xcodeproj")
        try makeFolder(named: "Target-bbbbbbbbbbbbbbbbbbbbbbbbbbbb", claiming: "/Projects/Target/Target.xcodeproj")

        let found = WorkspaceLocator.derivedData(
            forWorkspaceAt: URL(fileURLWithPath: "/Projects/Target/Target.xcodeproj"),
            in: derivedData
        )

        XCTAssertEqual(found?.lastPathComponent, "Target-bbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    }

    func testSharedCachesAreIgnoredBecauseTheyHaveNoInfoPlist() throws {
        try makeFolder(named: "ModuleCache.noindex", claiming: nil)
        try makeFolder(named: "SymbolCache.noindex", claiming: nil)

        let found = WorkspaceLocator.derivedData(
            forWorkspaceAt: URL(fileURLWithPath: "/Projects/Target/Target.xcodeproj"),
            in: derivedData
        )

        XCTAssertNil(found)
    }

    func testUnknownWorkspaceResolvesToNilRatherThanGuessing() throws {
        try makeFolder(named: "Target-cccccccccccccccccccccccccccc", claiming: "/Projects/Target/Target.xcodeproj")

        let found = WorkspaceLocator.derivedData(
            forWorkspaceAt: URL(fileURLWithPath: "/Projects/Elsewhere/Elsewhere.xcodeproj"),
            in: derivedData
        )

        XCTAssertNil(found)
    }

    func testNameSimilarityIsNotEnoughToMatch() throws {
        try makeFolder(named: "Target-dddddddddddddddddddddddddddd", claiming: "/Users/someone/Target/Target.xcodeproj")

        let found = WorkspaceLocator.derivedData(
            forWorkspaceAt: URL(fileURLWithPath: "/Users/other/Target/Target.xcodeproj"),
            in: derivedData
        )

        XCTAssertNil(found)
    }

    func testThisProjectResolvesOnThisMachine() throws {
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "MacEngine.xcodeproj", directoryHint: .isDirectory)

        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: project.path),
            "Source tree not present in this run"
        )

        let found = WorkspaceLocator.derivedData(forWorkspaceAt: project)
        XCTAssertNotNil(found, "MacEngine has been built, so DerivedData should claim it")
        XCTAssertTrue(found?.lastPathComponent.hasPrefix("MacEngine-") == true)
    }
}
