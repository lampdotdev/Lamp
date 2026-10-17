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

    /// Gives the test a folder of its own for sharing's folders (`Sharing.workFolder`), and fails it if any is
    /// still there once its teardown blocks have run. Called from `setUp`, so its own block runs last.
    func expectNoSharingFoldersLeft() {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-sharing-work-\(UUID().uuidString)")
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        Sharing.workFolder = folder
        addTeardownBlock {
            XCTAssertEqual((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [], [], "left in the temporary folder")
            Sharing.workFolder = fm.temporaryDirectory
            try? fm.removeItem(at: folder)
        }
    }
}
