import XCTest
@testable import Foliow

final class DeletionTests: XCTestCase {
    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func write(_ name: String, in root: URL, data: Data = Data([1, 2, 3])) throws -> URL {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
    func testOnlyPassedOriginalIsDeleted() throws {
        let root = try makeFolder()
        let keep = try write("keep.jpg", in: root)
        let pass = try write("pass.CR2", in: root)
        let unreviewed = try write("unreviewed.heic", in: root)
        var items = try FileService.scan(root, prior: [])
        for i in items.indices {
            if items[i].name == "keep.jpg" { items[i].decision = .keep }
            if items[i].name == "pass.CR2" { items[i].decision = .pass }
        }
        let result = FileService.deletePassed(DeletionRules.candidates(in: items), root: root)
        XCTAssertEqual(result.deletedIDs.count, 1)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pass.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unreviewed.path))
    }
    func testChangedFileIsNotDeleted() throws {
        let root = try makeFolder()
        let url = try write("pass.CR2", in: root)
        var item = try XCTUnwrap(FileService.scan(root, prior: []).first)
        item.decision = .pass
        try Data([1, 2, 3, 4, 5, 6]).write(to: url)
        let result = FileService.deletePassed([item], root: root)
        XCTAssertTrue(result.deletedIDs.isEmpty)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testKeepCannotBeSubmittedDirectlyForDeletion() throws {
        let root = try makeFolder()
        let url = try write("keep.jpg", in: root)
        var item = try XCTUnwrap(FileService.scan(root, prior: []).first)
        item.decision = .keep
        let result = FileService.deletePassed([item], root: root)
        XCTAssertTrue(result.deletedIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testParentPathTraversalCannotBeDeleted() throws {
        let root = try makeFolder()
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".jpg")
        try Data([5]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let item = PhotoItem(id: "escape", name: outside.lastPathComponent, origin: .files,
                             relativePath: "../" + outside.lastPathComponent, assetIdentifier: nil,
                             fingerprint: try FileService.fingerprint(outside), decision: .pass)
        let result = FileService.deletePassed([item], root: root)
        XCTAssertTrue(result.deletedIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
    func testSiblingFolderIsNotDescendant() {
        XCTAssertFalse(DeletionRules.isDescendant(URL(fileURLWithPath: "/tmp/photos-extra/a.jpg"), of: URL(fileURLWithPath: "/tmp/photos")))
        XCTAssertTrue(DeletionRules.isDescendant(URL(fileURLWithPath: "/tmp/photos/sub/a.jpg"), of: URL(fileURLWithPath: "/tmp/photos")))
    }
    func testRescanRestoresUnchangedDecisionsAndResetsChangedFiles() throws {
        let root = try makeFolder()
        let url = try write("a.jpg", in: root)
        var first = try FileService.scan(root, prior: [])
        first[0].decision = .pass
        XCTAssertEqual(try FileService.scan(root, prior: first).first?.decision, .pass)
        try Data([4, 5, 6, 7]).write(to: url)
        XCTAssertNil(try FileService.scan(root, prior: first).first?.decision)
    }
    func testSymlinkOutsideFolderIsNotScanned() throws {
        let root = try makeFolder()
        let other = try makeFolder()
        let original = try write("other.jpg", in: other)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.jpg"), withDestinationURL: original)
        XCTAssertTrue(try FileService.scan(root, prior: []).isEmpty)
    }
}
