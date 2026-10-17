import XCTest
@testable import Lamp

/// The keys a phone app keeps are sealed with a secret the phone's build carries. The app's token is in its folder,
/// where the agent's commands read it, so the secret must never be there too: with both, a command could ask the
/// gateway for the keys and open them. The phone's build still carries it, so the phone keeps getting its key.
final class PhoneSecretTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-phone-secret-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    func testAnIPhoneAppsFolderHoldsNoSecretItsPhoneBuildCarries() throws {
        try check(.iphone)
    }

    /// An app for both also writes a project into its own folder for its Mac half.
    func testAnAppForBothsFolderHoldsNoSecretItsPhoneBuildCarries() throws {
        try check(.universal)
    }

    private func check(_ platform: Platform) throws {
        let dir = work.appendingPathComponent("App")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        var app = LampProject(id: "tally", name: "Tally", exe: "Tally", dir: dir)
        app.platform = platform
        // Where an earlier Lamp kept it.
        let earlier = "MADE-UP-EARLIER-SECRET-" + UUID().uuidString
        try earlier.write(to: dir.appendingPathComponent(".lamp/phone-secret"), atomically: true, encoding: .utf8)

        try Template.writeOwnedFiles(for: app)
        let phoneBuild = work.appendingPathComponent("Phone Builds/tally")
        try Template.writeDeviceProject(for: app, team: "ABCDE12345", in: phoneBuild)

        func appFiles() -> [(name: String, text: String)] {
            FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)!.compactMap { item in
                guard let file = item as? URL, let data = try? Data(contentsOf: file) else { return nil }
                return (file.lastPathComponent, String(decoding: data, as: UTF8.self))
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".lamp/phone-secret").path),
                       "the earlier secret is still in the app's folder")
        for file in appFiles() where file.text.contains(earlier) {
            XCTFail("\(file.name) in the app's folder holds the earlier secret")
        }

        let plist = try XCTUnwrap(NSDictionary(contentsOf: phoneBuild.appendingPathComponent("Info.plist")))
        let secret = try XCTUnwrap(plist["LampPhoneSecret"] as? String, "the phone's build carries no secret to open its keys with")
        XCTAssertGreaterThanOrEqual(secret.count, 32)
        for file in appFiles() where file.text.contains(secret) {
            XCTFail("\(file.name) in the app's folder holds the phone's secret")
        }
    }
}
