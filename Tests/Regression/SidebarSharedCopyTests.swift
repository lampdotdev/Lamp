import XCTest
@testable import LampSidebarKit

/// The chat's Share… keeps the file it hands to the share menu. A service may still be reading the file from an
/// earlier share (an upload to a chat, a mail being written) when the person shares again, so that file must stay
/// where it was handed on, and sharing again and again must still leave one file.
final class SidebarSharedCopyTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-sidebar-share-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func shared(name: String, data: Data) -> SidebarSharing {
        SidebarSharing(id: UUID(), file: SidebarFile(name: name, data: data))
    }

    /// The names of the shared files kept, wherever under the folder they are.
    private func files() throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".lampapp") }
            .map { ($0 as NSString).lastPathComponent }
    }

    func testFileHandedOnStaysWhenSharedAgain() throws {
        let first = Data("first".utf8), second = Data("second".utf8)
        let handedOn = try SharedCopy.keep(shared(name: "Tally.lampapp", data: first), in: folder)
        // A service that has begun reading the first file.
        let reading = try FileHandle(forReadingFrom: handedOn)
        defer { try? reading.close() }
        let next = try SharedCopy.keep(shared(name: "Tally.lampapp", data: second), in: folder)
        // One that reads it only now still finds a whole file where it was handed on.
        XCTAssertEqual(next, handedOn)
        XCTAssertEqual(try? Data(contentsOf: handedOn), second)
        // The one already reading gets the file it began with, whole.
        XCTAssertEqual(try reading.readToEnd(), first)
        XCTAssertEqual(try files(), ["Tally.lampapp"])
    }

    /// An app renamed since it was last shared: the copy under its old name goes, so there's one file.
    func testOneFileAfterRenaming() throws {
        _ = try SharedCopy.keep(shared(name: "Tally.lampapp", data: Data("a".utf8)), in: folder)
        let renamed = try SharedCopy.keep(shared(name: "Counter.lampapp", data: Data("b".utf8)), in: folder)
        XCTAssertEqual(renamed.lastPathComponent, "Counter.lampapp")
        XCTAssertEqual(try files(), ["Counter.lampapp"])
    }
}
