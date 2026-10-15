import XCTest
@testable import Lamp

/// Lamp keeps a Mac app's secrets for it and hands them only to the app itself. These run real processes: a small
/// program signed into an app bundle, connecting to a port the test listens on, and others that know the port but
/// aren't that app.
final class AppSecretsTests: XCTestCase {
    private var work: URL!
    private var listener: Int32 = -1
    private var port: UInt16 = 0
    private var running: [Process] = []

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-app-secrets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        listener = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, length) } }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(listener, 8), 0)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) } }
        port = UInt16(bigEndian: address.sin_port)
    }

    override func tearDownWithError() throws {
        for process in running where process.isRunning { process.terminate() }
        close(listener)
        try? FileManager.default.removeItem(at: work)
    }

    // MARK: - Who is asking

    /// The app's own program, running from where it's installed, is the app; the same program run from elsewhere,
    /// `curl` sending what the app would, and the app's program once the installed copy is signed as something
    /// else are not.
    func testOnlyTheInstalledAppIsTheApp() throws {
        let app = try makeApp(named: "Installed")
        XCTAssertTrue(try caller(running: app.appendingPathComponent("Contents/MacOS/client"), checkedAgainst: app), "the app itself")

        // A whole copy of the app, signature and all, somewhere the agent can write.
        let elsewhere = work.appendingPathComponent("Copy.app")
        try FileManager.default.copyItem(at: app, to: elsewhere)
        XCTAssertFalse(try caller(running: elsewhere.appendingPathComponent("Contents/MacOS/client"), checkedAgainst: app),
                       "a copy of the app, run from another place")

        XCTAssertFalse(try caller(running: URL(fileURLWithPath: "/usr/bin/curl"), arguments: ["-s", "-m", "5", "http://127.0.0.1:\(port)/app/secrets"],
                                  checkedAgainst: app), "curl")

        // Running from the installed place, but what's installed there is now signed as another app.
        let client = try start(app.appendingPathComponent("Contents/MacOS/client"))
        XCTAssertEqual(try shell("codesign -f -s - -i dev.test.other \"\(app.path)\" 2>&1").status, 0)
        XCTAssertFalse(try accepted(from: client, checkedAgainst: app), "a program the installed copy no longer vouches for")
    }

    // MARK: - Where it's kept

    /// What one app kept is its own, and goes when that app is deleted; another app's stays.
    func testEachAppsSecretsAreItsOwnAndGoWithIt() throws {
        let service = "dev.lamp.test.app-secrets.\(UUID().uuidString)"
        let places: [AppSecrets.Place] = [.file(work.appendingPathComponent("app-secrets.json")), .keychain(service: service)]
        for place in places {
            XCTAssertTrue(AppSecrets.save(Data("one".utf8), as: "lamp-service-linear", app: "notes", in: place))
            XCTAssertTrue(AppSecrets.save(Data("two".utf8), as: "lamp-service-linear", app: "notesapp", in: place))
            XCTAssertNil(AppSecrets.read("lamp-service-linear", app: "other", in: place))
            AppSecrets.forget(app: "notes", in: place)
            XCTAssertNil(AppSecrets.read("lamp-service-linear", app: "notes", in: place), "\(place)")
            XCTAssertEqual(AppSecrets.read("lamp-service-linear", app: "notesapp", in: place), Data("two".utf8), "\(place)")
            AppSecrets.forget(app: "notesapp", in: place)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: work.appendingPathComponent("app-secrets.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testANameCantReachAnotherAppsSecrets() {
        XCTAssertTrue(AppSecrets.isName("lamp-service-linear"))
        for name in ["", "../notes/lamp-service-linear", "notes/lamp-service-linear", String(repeating: "a", count: 65), "naïve"] {
            XCTAssertFalse(AppSecrets.isName(name), name)
        }
    }

    // MARK: - Helpers

    /// An app bundle holding a program that connects to the test's port and waits, signed ad hoc as an app is.
    private func makeApp(named name: String) throws -> URL {
        let source = work.appendingPathComponent("client.swift")
        try """
        import Foundation
        let s = socket(AF_INET, SOCK_STREAM, 0)
        var a = sockaddr_in()
        a.sin_family = sa_family_t(AF_INET)
        a.sin_addr.s_addr = inet_addr("127.0.0.1")
        a.sin_port = UInt16(CommandLine.arguments[1])!.bigEndian
        let c = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard c == 0 else { exit(1) }
        sleep(30)
        """.write(to: source, atomically: true, encoding: .utf8)
        let app = work.appendingPathComponent("\(name).app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.test.app</string><key>CFBundleExecutable</key><string>client</string></dict></plist>
        """.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        let built = try shell(Shell.compatibleSDK + "xcrun swiftc -O -o \"\(macOS.path)/client\" \"\(source.path)\" 2>&1")
        XCTAssertEqual(built.status, 0, built.output)
        let signed = try shell("codesign -s - -i dev.test.app \"\(app.path)\" 2>&1")
        XCTAssertEqual(signed.status, 0, signed.output)
        return app
    }

    private func start(_ program: URL, arguments: [String]? = nil) throws -> Process {
        let process = Process()
        process.executableURL = program
        process.arguments = arguments ?? [String(port)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        running.append(process)
        return process
    }

    private func caller(running program: URL, arguments: [String]? = nil, checkedAgainst app: URL) throws -> Bool {
        let process = try start(program, arguments: arguments)
        return try accepted(from: process, checkedAgainst: app)
    }

    /// Takes the next connection and asks whether it comes from the app; the connection stays open while asking.
    private func accepted(from process: Process, checkedAgainst app: URL) throws -> Bool {
        var ready = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&ready, 1, 10_000), 1, "nothing connected")
        var peer = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let connection = withUnsafeMutablePointer(to: &peer) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.accept(listener, $0, &length) } }
        defer { close(connection); process.terminate() }
        return PeerProcess.isApp(at: app, connectedFrom: UInt16(bigEndian: peer.sin_port), to: port)
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
