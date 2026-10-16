import XCTest
@testable import Lamp

/// A wish dragged off the desk hands over its shared file, which the app it's dropped on may read long after the
/// drag. Dragging the same wish again makes the file again in the same place, so drags don't pile up.
final class DeskDragTests: XCTestCase {
    private var root: URL?
    override func setUp() { expectNoSharingFoldersLeft() }
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func project() throws -> LampProject {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-drag-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("tally")
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "let count = 0".write(to: dir.appendingPathComponent("Sources/ContentView.swift"), atomically: true, encoding: .utf8)
        return LampProject(id: "tally", name: "Tally", exe: "Tally", dir: dir)
    }

    func testDraggingAgainLeavesOneFile() throws {
        let project = try project()
        let shared = try XCTUnwrap(root).appendingPathComponent("Shared")
        let first = try WishDrag.Payload(project: project, app: nil, in: shared) {}.sharedFile()
        // The app the first drag was dropped on still has its file while the second drag is made.
        let read = try FileHandle(forReadingFrom: first)
        defer { try? read.close() }
        let second = try WishDrag.Payload(project: project, app: nil, in: shared) {}.sharedFile()
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: shared.path), ["Tally.lampapp"])
        XCTAssertEqual(second, first)
        XCTAssertNoThrow(try opened(second))
        XCTAssertFalse(try XCTUnwrap(read.readToEnd()).isEmpty)
    }
}
