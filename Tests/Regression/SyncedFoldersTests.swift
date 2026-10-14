import XCTest
@testable import Lamp

/// `LampFolders.synced` tells a generated app where the person's synced files are. Google Drive names its My Drive
/// folder in the Mac's language ("Meine Ablage" in German), and an app that is handed the account's folder instead
/// looks for "Invoices" one level too high. The helper is cut out of the template, compiled and run against a
/// made-up home folder.
final class SyncedFoldersTests: XCTestCase {
    func testGoogleDrivePointsAtMyDriveWhateverItIsCalled() throws {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "enum LampFolders {"))
        let end = try XCTUnwrap(support.range(of: "// end LampFolders", range: start.upperBound..<support.endIndex))
        let program = """
        import Foundation
        \(support[start.lowerBound..<end.lowerBound])
        for folder in LampFolders.synced {
            print(folder.service, folder.account ?? "-", folder.url.path.replacingOccurrences(of: NSHomeDirectory() + "/", with: ""))
        }
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-synced-\(UUID().uuidString)")
        let home = work.appendingPathComponent("home")
        defer { try? FileManager.default.removeItem(at: work) }
        let storage = "Library/CloudStorage/"
        for folder in [
            storage + "GoogleDrive-sam@example.com/My Drive",
            storage + "GoogleDrive-sam@example.com/Shared drives",
            storage + "GoogleDrive-kai@example.de/Meine Ablage",
            storage + "GoogleDrive-kai@example.de/Geteilte Ablagen",
            storage + "GoogleDrive-ana@example.es/Mi unidad",
            storage + "GoogleDrive-new@example.com/Root of a language Lamp doesn't know",
            storage + "Dropbox",
            storage + "OneDrive-Personal",
            "Library/Mobile Documents/com~apple~CloudDocs"
        ] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = try run(Shell.compatibleSDK + "xcrun swiftc -o synced main.swift 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        let printed = try run("CFFIXED_USER_HOME=\(home.path) ./synced", in: work).output
        XCTAssertEqual(printed, """
        iCloud Drive - Library/Mobile Documents/com~apple~CloudDocs
        Dropbox - Library/CloudStorage/Dropbox
        Google Drive ana@example.es Library/CloudStorage/GoogleDrive-ana@example.es/Mi unidad
        Google Drive kai@example.de Library/CloudStorage/GoogleDrive-kai@example.de/Meine Ablage
        Google Drive new@example.com Library/CloudStorage/GoogleDrive-new@example.com/Root of a language Lamp doesn't know
        Google Drive sam@example.com Library/CloudStorage/GoogleDrive-sam@example.com/My Drive
        OneDrive Personal Library/CloudStorage/OneDrive-Personal

        """)
    }

    private func run(_ command: String, in directory: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
