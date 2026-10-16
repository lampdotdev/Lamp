import XCTest
@testable import Lamp

/// Exporting and opening a shared app each make a folder in the temporary folder and hand it on: whoever takes the
/// file or the unpacked app removes it, as Lamp does. Tests take them too, so they remove them, and each test that
/// shares checks that it left none, since nothing else empties the temporary folder.
extension XCTestCase {
    /// `Sharing.export`, with the folder it was made in removed once the test is done.
    func exported(_ project: LampProject, icon: Data? = nil) throws -> URL {
        let file = try Sharing.export(project, icon: icon)
        addTeardownBlock { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        return file
    }

    /// `Sharing.open`, with the unpacked app removed once the test is done.
    func opened(_ file: URL) throws -> Sharing.Package {
        let package = try Sharing.open(file)
        addTeardownBlock { try? FileManager.default.removeItem(at: package.folder) }
        return package
    }

    /// Fails the test if a folder sharing makes appears while it runs and is still there once its teardown blocks
    /// have run. Called from `setUp`, so its own block runs last. What's found is left alone: Lamp itself, sharing at
    /// the same moment, makes folders by these names too.
    func expectNoSharingFoldersLeft() {
        let before = Self.sharingFolders()
        addTeardownBlock {
            XCTAssertEqual(Self.sharingFolders().subtracting(before), [], "left in the temporary folder")
        }
    }

    private static func sharingFolders() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
        return Set(names.filter { $0.hasPrefix("forge-share-") || $0.hasPrefix("forge-import-") })
    }
}
