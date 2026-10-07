import Foundation

@main struct Replay {
    struct Fixture: Decodable {
        let file: String
        let stage: String
        let cause: String
        let provenance: String
    }
    static func check(_ condition: Bool, _ label: String) {
        if !condition { fatalError("FAIL: \(label)") }
        print("PASS: \(label)")
    }

    @MainActor static func main() async throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
        let rows = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: fixtures.appendingPathComponent("manifest.json")))
        let expectedMessages = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixtures.appendingPathComponent("messages.json")))
        var messages: [String: String] = [:]
        for row in rows where !row.cause.isEmpty {
            let output = try String(contentsOf: fixtures.appendingPathComponent(row.file), encoding: .utf8)
            let failure = PhoneFailure(stage: PhoneFailure.Stage(rawValue: row.stage)!, output: output)
            check(failure.cause.rawValue == row.cause, "\(row.file) → \(row.cause) [\(row.provenance)]")
            check(failure.message == expectedMessages[row.cause], "\(row.file) keeps the approved directions")
            messages[row.file] = failure.message
        }
        check(PhoneFailure(stage: .build, output: "No Accounts\n" + (try String(contentsOf: fixtures.appendingPathComponent("capability.txt"), encoding: .utf8))).cause == .capability, "specific capability cause beats No Accounts")
        check(PhoneFailure(stage: .build, output: "Provisioning profile could not be made: certificate has expired").cause == .certificate, "certificate expiry is not profile expiry")
        check(PhoneFailure(stage: .build, output: "Swift error: cannot find value 'example' in scope").cause == .build, "compiler failure stays a build failure")
        check(PhoneFailure(stage: .build, output: "Command line invocation: DEVELOPMENT_TEAM=TESTTEAM01\nCodeSign /tmp/App.app\nProvisioning profile installed\nSources/App.swift:12:4: error: cannot find value").cause == .build, "successful signing noise cannot hide a Swift error")
        check(PhoneFailure(stage: .install, output: "Unexpected installer error").cause == .install, "unknown install stays an install failure")
        check(PhoneFailure(stage: .build, output: "Your session has expired").cause == .authentication, "expired login has its own advice")
        check(PhoneFailure(stage: .build, output: "errSecInternalComponent").cause == .certificate, "keychain failure has certificate advice")
        let extraMessages: [(PhoneFailure.Stage, String)] = [
            (.build, "Authentication failed"), (.build, "No profiles for dev.example.app"),
            (.build, "Compiler failed"), (.install, "Installer failed"),
            (.launch, "Launch failed"), (.install, "Developer mode is disabled")
        ]
        for (stage, output) in extraMessages {
            let failure = PhoneFailure(stage: stage, output: output)
            check(failure.message == expectedMessages[failure.cause.rawValue], "\(failure.cause) keeps the approved directions")
        }
        let unnamedCapability = PhoneFailure(stage: .build, output: "Entitlement not supported")
        check(unnamedCapability.message == expectedMessages["capability"]?.replacingOccurrences(of: "Push Notifications", with: "a feature this app uses"), "capability without a name keeps a readable placeholder")
        let bundle = "com.companyname.mauiapp1"
        let success = try String(contentsOf: fixtures.appendingPathComponent("launch-confirmed.txt"), encoding: .utf8)
        check(PhoneLaunch.acknowledged(success, bundleID: bundle), "real launch confirmation accepted")
        check(!PhoneLaunch.acknowledged(success, bundleID: "other.bundle"), "another app's acknowledgement rejected")
        check(!PhoneLaunch.acknowledged("Acquired tunnel connection to device.", bundleID: bundle), "a tunnel is not a launch")
        // Replay through real subprocesses and the production asynchronous waiter, rather than calling only
        // its line matcher. Exit status, delayed output, timeout and cancellation all matter here.
        try await launchReplay(fixtures.appendingPathComponent("launch-confirmed.txt"), bundle: bundle, delay: "0.4", hold: "2", timeout: 2, expected: nil)
        try await launchReplay(fixtures.appendingPathComponent("launch-security.txt"), bundle: bundle, hold: "0", expected: .launchSecurity)
        try await launchReplay(fixtures.appendingPathComponent("local-launch-security.txt"), bundle: bundle, hold: "0", expected: .launchSecurity)
        try await launchReplay(fixtures.appendingPathComponent("unreachable.txt"), bundle: bundle, hold: "0", expected: .unreachable)
        try await launchReplay(fixtures.appendingPathComponent("locked.txt"), bundle: bundle, hold: "0", expected: .locked)
        try await launchReplay(fixtures.appendingPathComponent("unreachable.txt"), bundle: bundle, hold: "2", timeout: 0.2, expected: .unreachable)
        try await launchReplay(fixtures.appendingPathComponent("launch-confirmed.txt"), bundle: "other.bundle", hold: "0", exit: "0", expected: .launch)
        try await launchReplay(fixtures.appendingPathComponent("launch-confirmed.txt"), bundle: bundle, hold: "0", exit: "0", waitExited: true, expected: .launch)
        try await launchReplay(fixtures.appendingPathComponent("launch-confirmed.txt"), bundle: bundle, delay: "1", hold: "1", timeout: 0.2, expected: .launch)
        try await launchReplay(fixtures.appendingPathComponent("unreachable.txt"), bundle: bundle, hold: "2", timeout: 0.2, prefix: success, expected: .unreachable)
        try await launchReplay(fixtures.appendingPathComponent("launch-confirmed.txt"), bundle: bundle, delay: "1", hold: "1", cancel: true, expected: nil)
        if CommandLine.arguments.count > 2 {
            try JSONSerialization.data(withJSONObject: messages, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        }
        print("All phone failure and launch replays passed. No physical device used.")
    }

    @MainActor static func launchReplay(_ fixture: URL, bundle: String, delay: String = "0", hold: String,
                                        exit status: String = "1", timeout: TimeInterval = 1,
                                        cancel: Bool = false, prefix: String = "", waitExited: Bool = false, expected: PhoneFailure.Cause?) async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: log.path, contents: Data(prefix.utf8))
        let handle = try FileHandle(forWritingTo: log)
        let offset = handle.seekToEndOfFile()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep \"$2\"; cat \"$1\"; sleep \"$3\"; exit \"$4\"", "replay", fixture.path, delay, hold, status]
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        defer { if process.isRunning { process.terminate() }; try? handle.close(); try? FileManager.default.removeItem(at: log) }
        if waitExited {
            while process.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        }
        let started = Date()
        do {
            try await PhoneLaunch.wait(process, bundleID: bundle, output: log, offset: offset, timeout: timeout,
                                       cancelled: { cancel && Date().timeIntervalSince(started) > 0.2 })
            check(expected == nil && !cancel, "console waits for delayed acknowledgement")
            check(Date().timeIntervalSince(started) >= 0.4, "no ready before launch output arrives")
        } catch is CancellationError {
            check(cancel, "stopped launch never becomes ready")
        } catch let failure as PhoneFailure {
            check(failure.cause == expected, "launch waiter surfaces \(fixture.lastPathComponent) as \(failure.cause)")
        }
    }
}
