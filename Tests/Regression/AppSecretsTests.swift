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

    /// What the build stamps into every app (buildSh's __RESTRICT segment): dyld ignores
    /// DYLD_INSERT_LIBRARIES for the app, so nothing can be ridden into it to ask Lamp for its secrets as
    /// the app. The same program built without it takes the library; with it the library never runs and the
    /// app is still the app to Lamp.
    func testABuiltAppTakesNoInjectedLibrary() throws {
        let marker = work.appendingPathComponent("injected")
        let library = work.appendingPathComponent("inj.dylib")
        let source = work.appendingPathComponent("inj.c")
        try """
        #include <stdio.h>
        __attribute__((constructor)) static void go(void) { FILE *f = fopen("\(marker.path)", "w"); if (f) fclose(f); }
        """.write(to: source, atomically: true, encoding: .utf8)
        let built = try shell(Shell.compatibleSDK + "xcrun clang -dynamiclib -o \"\(library.path)\" \"\(source.path)\" 2>&1")
        XCTAssertEqual(built.status, 0, built.output)

        let plain = try makeApp(named: "Plain")
        let injected = try start(plain.appendingPathComponent("Contents/MacOS/client"),
                                 environment: ["DYLD_INSERT_LIBRARIES": library.path])
        XCTAssertTrue(try accepted(from: injected, checkedAgainst: plain), "the plain app, library and all, is the app")
        waitFor(injected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "without __RESTRICT the library runs in the app")

        try FileManager.default.removeItem(at: marker)
        let restricted = try makeApp(named: "Restricted", restrict: true)
        let clean = try start(restricted.appendingPathComponent("Contents/MacOS/client"),
                              environment: ["DYLD_INSERT_LIBRARIES": library.path])
        XCTAssertTrue(try accepted(from: clean, checkedAgainst: restricted), "the restricted app is still the app")
        waitFor(clean)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "with __RESTRICT the library never runs")
    }

    /// Waits for a process that should end on its own, and ends one that won't (the client waits 30s).
    private func waitFor(_ process: Process) {
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate() }
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

    /// A delete says whether it's forgotten: not when the file is there but can't be read, since it may still hold it;
    /// yes when nothing was kept at all.
    func testADeleteThatCantReadTheFileIsntDone() throws {
        let url = work.appendingPathComponent("unreadable.json")
        XCTAssertTrue(AppSecrets.delete("lamp-api-readwise", app: "notes", in: .file(url)))
        XCTAssertTrue(AppSecrets.save(Data("token".utf8), as: "lamp-api-readwise", app: "notes", in: .file(url)))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        XCTAssertFalse(AppSecrets.delete("lamp-api-readwise", app: "notes", in: .file(url)))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        XCTAssertEqual(AppSecrets.read("lamp-api-readwise", app: "notes", in: .file(url)), Data("token".utf8))
        XCTAssertTrue(AppSecrets.delete("lamp-api-readwise", app: "notes", in: .file(url)))
        XCTAssertNil(AppSecrets.read("lamp-api-readwise", app: "notes", in: .file(url)))
    }

    /// One app can't fill Lamp's store: past the limit a new name is refused, and what's kept can still change.
    func testAnAppKeepsAtMostItsLimit() throws {
        let service = "dev.lamp.test.app-secrets.\(UUID().uuidString)"
        for place: AppSecrets.Place in [.file(work.appendingPathComponent("limit.json")), .keychain(service: service)] {
            for index in 0..<AppSecrets.limit { XCTAssertTrue(AppSecrets.save(Data("x".utf8), as: "name-\(index)", app: "full", in: place)) }
            XCTAssertFalse(AppSecrets.save(Data("x".utf8), as: "one-more", app: "full", in: place), "\(place)")
            XCTAssertTrue(AppSecrets.save(Data("y".utf8), as: "name-0", app: "full", in: place), "\(place)")
            AppSecrets.forget(app: "full", in: place)
        }
    }

    func testANameCantReachAnotherAppsSecrets() {
        XCTAssertTrue(AppSecrets.isName("lamp-service-linear"))
        for name in ["", "../notes/lamp-service-linear", "notes/lamp-service-linear", String(repeating: "a", count: 65), "naïve"] {
            XCTAssertFalse(AppSecrets.isName(name), name)
        }
    }

    // MARK: - Helpers

    /// An app bundle holding a program that connects to the test's port and waits, signed ad hoc as an app
    /// is. `restrict` adds the __RESTRICT segment buildSh gives every app Lamp builds.
    private func makeApp(named name: String, restrict: Bool = false) throws -> URL {
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
        var restrictFlags = ""
        if restrict {
            let empty = work.appendingPathComponent("restrict")
            try Data().write(to: empty)
            restrictFlags = " -Xlinker -sectcreate -Xlinker __RESTRICT -Xlinker __restrict -Xlinker \"\(empty.path)\""
        }
        let built = try shell(Shell.compatibleSDK + "xcrun swiftc -O\(restrictFlags) -o \"\(macOS.path)/client\" \"\(source.path)\" 2>&1")
        XCTAssertEqual(built.status, 0, built.output)
        let signed = try shell("codesign -s - -i dev.test.app \"\(app.path)\" 2>&1")
        XCTAssertEqual(signed.status, 0, signed.output)
        return app
    }

    private func start(_ program: URL, arguments: [String]? = nil, environment: [String: String]? = nil) throws -> Process {
        let process = Process()
        process.executableURL = program
        process.arguments = arguments ?? [String(port)]
        if let environment { process.environment = environment }
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
        TestShell.run(command)
    }
}
