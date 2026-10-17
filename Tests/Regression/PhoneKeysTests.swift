import XCTest
@testable import Lamp

/// A phone app's AI goes only through Lamp on the Mac: its code is the agent's to write, so nothing that is or
/// unlocks one of the person's keys may reach the phone, and a key an earlier Lamp let a phone keep is dropped.
final class PhoneKeysTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-phone-keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work.appendingPathComponent("App/.lamp"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("App/Sources"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private var app: LampProject {
        var project = LampProject(id: "tally", name: "Tally", exe: "Tally", dir: work.appendingPathComponent("App"))
        project.platform = .iphone
        return project
    }

    /// An earlier Lamp sealed the keys it handed a phone with a secret kept in the app's folder and written into
    /// its LampSupport.swift, both of which the agent can read. Lamp's own files for the app carry it no more,
    /// and the secret goes.
    func testTheAppsFilesCarryNothingThatUnlocksAKey() throws {
        let secret = "MADE-UP-PHONE-SECRET-" + UUID().uuidString
        let file = app.dir.appendingPathComponent(".lamp/phone-secret")
        try secret.write(to: file, atomically: true, encoding: .utf8)

        try Template.writeOwnedFiles(for: app)

        let support = try String(contentsOf: app.dir.appendingPathComponent("Sources/LampSupport.swift"), encoding: .utf8)
        XCTAssertFalse(support.contains(secret), "the phone's code carries the secret")
        XCTAssertFalse(support.contains("/ai/keys"), "the phone's code still asks for keys")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "the secret is still in the app's folder")
    }

    /// A phone build drops what an earlier build kept in the Keychain as it loads, before the app's own code runs:
    /// the project compiles a load-time initializer into the app that deletes the item.
    func testAPhoneBuildDropsAKeptKeyBeforeTheAppRuns() throws {
        let folder = work.appendingPathComponent("Phone Builds/tally")
        try Template.writeDeviceProject(for: app, team: "ABCDE12345", in: folder)

        let source = folder.appendingPathComponent("LampForgetKeys.lamp-c")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the phone project has nothing that drops a kept key")
        let pbxproj = try String(contentsOf: folder.appendingPathComponent("Tally.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(pbxproj.contains("LampForgetKeys.lamp-c in Sources */); runOnlyForDeploymentPostprocessing"), "the app target doesn't compile it")

        guard (try? shell("xcrun --sdk iphoneos --show-sdk-path"))?.status == 0 else { throw XCTSkip("No iPhone SDK here.") }
        let object = work.appendingPathComponent("forget.o")
        let built = try shell("xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 -x c -c \"\(source.path)\" -o \"\(object.path)\" 2>&1")
        XCTAssertEqual(built.status, 0, built.output)
        let sections = try shell("xcrun otool -l \"\(object.path)\"").output
        XCTAssertTrue(sections.contains("__mod_init_func"), "it doesn't run as the app loads")
        let symbols = try shell("xcrun nm \"\(object.path)\"").output
        XCTAssertTrue(symbols.contains("_SecItemDelete"), "it doesn't delete the Keychain item")
    }

    private func shell(_ command: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
