import Foundation

final class PhoneToolsChecks {
    private let developer = "/Applications/Chosen Xcode.app/Contents/Developer"
    private let runtimes = #"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-17-0","version":"17.0","isAvailable":true}]}"#
    private let simulators = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[{"name":"iPhone 15","udid":"sim-phone","state":"Shutdown"},{"name":"iPad Air","udid":"sim-pad","state":"Shutdown"}]}}"#

    private func result(_ text: String = "", status: Int32 = 0, errors: String = "", timedOut: Bool = false) -> Subprocess.Result {
        .init(status: status, output: text, errors: errors, timedOut: timedOut)
    }

    private func probe(fail: PhoneTools.Step? = nil, phoneVersion: String? = "17.0", runtime: String? = nil,
                       commands: (([String]) -> Void)? = nil) -> PhoneTools.Probe {
        var p = probeWithoutAccount(fail: fail, phoneVersion: phoneVersion, runtime: runtime, commands: commands)
        p.hasViewer = { _ in true }
        p.teams = { fail == .account ? [] : [(id: "ABCDE12345", name: "Test Team")] }
        p.freeTeams = { [] }
        p.team = { "ABCDE12345" }
        p.chooseTeam = { _ in }
        return p
    }

    private func probeWithoutAccount(fail: PhoneTools.Step? = nil, phoneVersion: String? = "17.0", runtime: String? = nil,
                                     commands: (([String]) -> Void)? = nil) -> PhoneTools.Probe {
        .init(developer: { fail == .xcode ? nil : self.developer }, active: { fail == .tools ? "/Library/Developer/CommandLineTools" : self.developer }, run: { tool, args, env in
            expectEqual(env["DEVELOPER_DIR"], self.developer)
            commands?(args)
            if args == ["-checkFirstLaunchStatus"] {
                expectEqual(tool, self.developer + "/usr/bin/xcodebuild")
                return self.result(status: fail == .firstLaunch ? 1 : 0)
            }
            if args.contains("--show-sdk-path") { return self.result("/an/sdk", status: fail == .platform ? 1 : 0) }
            if args.contains("runtimes") { return self.result(runtime ?? (fail == .runtime ? #"{"runtimes":[]}"# : self.runtimes)) }
            if args.contains("simctl") { return self.result(fail == .simulator ? #"{"devices":{}}"# : self.simulators) }
            return self.result()
        }, read: { _ in
            guard let phoneVersion else { return nil }
            return """
            {"result":{"devices":[{"hardwareProperties":{"udid":"phone"},"deviceProperties":{"name":"Test iPhone","osVersionNumber":"\(phoneVersion)"}}]}}
            """.data(using: .utf8)
        })
    }

    func testStopsAtEachPrerequisiteAndDoesNotProbeLaterSteps() {
        let steps = PhoneTools.Step.allCases.filter { $0 != .phone && $0 != .account }
        for (index, step) in steps.enumerated() {
            var commands = [[String]]()
            let report = PhoneTools.check(probe: probe(fail: step, commands: { commands.append($0) }))
            expectEqual(report.issue?.step, step)
            expectEqual(report.passed, Array(steps.prefix(index)))
            if step == .xcode || step == .tools { expectTrue(commands.isEmpty) }
            if step == .firstLaunch { expectEqual(commands, [["-checkFirstLaunchStatus"]]) }
            if step == .platform { expectFalse(commands.contains { $0.contains("simctl") }) }
        }
    }

    func testActionsMatchTheBlocker() {
        let actions: [PhoneTools.Step: PhoneTools.Action] = [.xcode: .installXcode, .tools: .useXcode,
            .firstLaunch: .openXcode, .platform: .components, .runtime: .components, .simulator: .simulator]
        for (step, action) in actions { expectEqual(PhoneTools.check(probe: probe(fail: step)).issue?.action, action) }
    }

    func testLicenseAndFirstLaunchAreSeparateMessages() {
        var p = probe()
        p.run = { _, _, _ in self.result(status: 1, errors: "You have not agreed to the Xcode license agreements") }
        expectEqual(PhoneTools.check(probe: p).issue?.title, "Accept Xcode's agreements")
        p.run = { _, _, _ in self.result(status: 1, errors: "Additional components need to be installed") }
        expectEqual(PhoneTools.check(probe: p).issue?.title, "Finish Xcode setup")
        p.run = { _, _, _ in self.result(status: -1, timedOut: true) }
        expectEqual(PhoneTools.check(probe: p).issue?.title, "Xcode isn't responding")
    }

    func testUnavailableAndOldRuntimesDoNotPass() {
        for runtime in [
            #"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-17-0","version":"17.0","isAvailable":false}]}"#,
            #"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-16-4","version":"16.4","isAvailable":true}]}"#,
            #"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.tvOS-18-0","version":"18.0","isAvailable":true}]}"#
        ] { expectEqual(PhoneTools.check(probe: probe(runtime: runtime)).issue?.step, .runtime) }
    }

    func testSimulatorFailureIsNotDescribedAsAMissingDownload() {
        var p = probe()
        let run = p.run
        p.run = { tool, args, env in args.contains("runtimes") ? self.result("service unavailable", status: 1) : run(tool, args, env) }
        expectEqual(PhoneTools.check(probe: p).issue?.title, "The simulator isn't responding")
        expectEqual(PhoneTools.check(probe: probe(runtime: "bad JSON")).issue?.title, "The simulator isn't responding")
    }

    func testBothSDKsMustBeAvailable() {
        var p = probe()
        let run = p.run
        p.run = { tool, args, env in args.contains("iphonesimulator") ? self.result(status: 1) : run(tool, args, env) }
        expectEqual(PhoneTools.check(probe: p).issue?.step, .platform)
    }

    func testPhoneVersionIsReadFromChosenDeviceAndUnknownIsNotReady() {
        let old = PhoneTools.check(phone: "phone", probe: probe(phoneVersion: "16.7.12"))
        expectEqual(old.issue?.step, .phone)
        expectEqual(old.issue?.action, .updatePhone)
        expectTrue(old.issue?.message.contains("16.7.12") == true)
        for version in ["17.0", "18.6", "26.0"] {
            let report = PhoneTools.check(phone: "phone", probe: probe(phoneVersion: version))
            expectTrue(report.ready)
            expectEqual(report.passed.last, .phone)
        }
        for version in [nil, "", "unknown"] as [String?] {
            expectEqual(PhoneTools.check(phone: "phone", probe: probe(phoneVersion: version)).issue?.action, .retry)
        }
        expectEqual(PhoneTools.check(phone: "different-phone", probe: probe()).issue?.action, .retry)
    }

    func testTheViewerIsSimulatorOrDeviceHubWhereverThisXcodeKeepsIt() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let developer = root.appendingPathComponent("Xcode.app/Contents/Developer").path
        try fm.createDirectory(atPath: developer, withIntermediateDirectories: true)
        expectEqual(PhoneTools.viewer(in: developer), nil)
        // Xcode 27 has Device Hub beside the other apps, with no Simulator in Developer.
        let hub = root.appendingPathComponent("Xcode.app/Contents/Applications/DeviceHub.app")
        try fm.createDirectory(at: hub, withIntermediateDirectories: true)
        expectEqual(PhoneTools.viewer(in: developer)?.lastPathComponent, "DeviceHub.app")
        // Earlier Xcodes have Simulator in Developer, which comes first.
        try fm.createDirectory(atPath: developer + "/Applications/Simulator.app", withIntermediateDirectories: true)
        expectEqual(PhoneTools.viewer(in: developer)?.lastPathComponent, "Simulator.app")
    }

    func testAnXcodeWithoutTheSimulatorAppIsNotReady() {
        var p = probe()
        p.hasViewer = { developer in expectEqual(developer, self.developer); return false }
        let report = PhoneTools.check(probe: p)
        expectEqual(report.issue?.step, .simulator)
        expectEqual(report.issue?.action, .components)
        expectEqual(report.passed.last, .runtime)
    }

    func testAccountIsCheckedOnlyForAPhoneAndASingleTeamIsChosenByItself() {
        // Without a phone, no account is needed, and Xcode's accounts aren't even asked for.
        var asked = false
        var p = probe()
        p.teams = { asked = true; return [] }
        expectTrue(PhoneTools.check(probe: p).ready)
        expectFalse(asked)
        // With one, no signed-in account stops the check before the phone is reached.
        var commands = [[String]]()
        let none = PhoneTools.check(phone: "phone", probe: probe(fail: .account, commands: { commands.append($0) }))
        expectEqual(none.issue?.step, .account)
        expectEqual(none.issue?.action, .openXcode)
        expectFalse(none.passed.contains(.phone))
        expectFalse(commands.contains { $0.contains("devicectl") })
        // One team signed in and none chosen: chosen now, and the check goes on.
        var chosen: String?
        p = probe()
        p.team = { "" }
        p.chooseTeam = { chosen = $0 }
        let single = PhoneTools.check(phone: "phone", probe: p)
        expectTrue(single.ready)
        expectEqual(chosen, "ABCDE12345")
        expectEqual(single.passed, PhoneTools.Step.allCases)
        // More than one and none of them chosen: the person decides, in Settings.
        p.teams = { [(id: "ABCDE12345", name: "Test Team"), (id: "FGHIJ67890", name: "Other Team")] }
        p.team = { "ZZZZZ00000" }
        chosen = nil
        let several = PhoneTools.check(phone: "phone", probe: p)
        expectEqual(several.issue?.step, .account)
        expectEqual(several.issue?.action, .settings)
        expectEqual(chosen, nil)
        // The chosen team among several: fine as it is.
        p.team = { "FGHIJ67890" }
        expectTrue(PhoneTools.check(phone: "phone", probe: p).ready)
    }

    func testAnAppThatKeepsDataInICloudIsNotReadyWithAFreeAccount() {
        var p = probe()
        p.freeTeams = { ["ABCDE12345"] }
        // On the person's phone and as the Mac half of an app for both: told before anything is built.
        for report in [PhoneTools.check(phone: "phone", requiresPaidTeam: true, probe: p),
                       PhoneTools.check(requiresTeam: true, requiresPaidTeam: true, probe: p)] {
            expectEqual(report.issue?.step, .account)
            expectEqual(report.issue?.action, .membership)
            expectTrue(report.issue?.message.contains("paid Apple Developer membership") == true)
            expectFalse(report.passed.contains(.account))
        }
        // The same account still passes for an app that doesn't use iCloud, and nothing looks up which teams are free.
        var asked = false
        p.freeTeams = { asked = true; return ["ABCDE12345"] }
        expectTrue(PhoneTools.check(phone: "phone", probe: p).ready)
        expectTrue(PhoneTools.check(requiresTeam: true, probe: p).ready)
        expectTrue(PhoneTools.check(probe: p).ready)
        expectFalse(asked)
        // A paid team passes.
        p.freeTeams = { [] }
        expectTrue(PhoneTools.check(phone: "phone", requiresPaidTeam: true, probe: p).ready)
        // A free team chosen while a paid one is signed in too: the fix is choosing the other.
        p.teams = { [(id: "ABCDE12345", name: "Test Person"), (id: "FGHIJ67890", name: "Test Company")] }
        p.freeTeams = { ["ABCDE12345"] }
        expectEqual(PhoneTools.check(phone: "phone", requiresPaidTeam: true, probe: p).issue?.action, .settings)
        p.team = { "FGHIJ67890" }
        expectTrue(PhoneTools.check(phone: "phone", requiresPaidTeam: true, probe: p).ready)
        // Nobody signed in: a free account isn't offered to an app it can't sign.
        let none = PhoneTools.check(phone: "phone", requiresPaidTeam: true, probe: probe(fail: .account))
        expectEqual(none.issue?.title, "Sign in to Xcode")
        expectFalse(none.issue?.message.contains("a free one will do") == true)
        expectTrue(PhoneTools.check(phone: "phone", probe: probe(fail: .account)).issue?.message.contains("a free one will do") == true)
    }

    func testXcodeSaysWhichTeamsAreFree() {
        // What Xcode 27 keeps for a signed-in free account, read on 2026-10-13 with the account, team ID and
        // name replaced. No paid team's record has been captured: the second one only lacks the mark.
        let accounts: [String: Any] = ["ACCOUNT": [
            ["isFreeProvisioningTeam": true, "teamID": "ABCDE12345", "teamName": "Test Person", "teamType": "Personal Team"],
            ["teamID": "FGHIJ67890", "teamName": "Test Company"],
        ]]
        expectEqual(PhoneTools.xcodeFreeTeams(in: accounts), ["ABCDE12345"])
    }

    func testReadyForBothFamiliesAndDoesNotNeedAPhysicalPhone() {
        for family in [DeviceFamily.iphone, .ipad] {
            var commands = [[String]]()
            let report = PhoneTools.check(family: family, probe: probe(commands: { commands.append($0) }))
            expectTrue(report.ready)
            expectFalse(report.passed.contains(.phone))
            expectFalse(commands.contains { $0.contains("devicectl") })
        }
    }

    func testRenamedXcodeAndCLTAreDistinguishedByBundleAndExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Renamed.app")
        let dev = app.appendingPathComponent("Contents/Developer")
        try FileManager.default.createDirectory(at: dev.appendingPathComponent("usr/bin"), withIntermediateDirectories: true)
        let tool = dev.appendingPathComponent("usr/bin/xcodebuild")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        expectFalse(PhoneTools.isXcode(dev.path))
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.apple.dt.Xcode"], format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        expectTrue(PhoneTools.isXcode(dev.path))
    }

    @MainActor
    func testXcodeChoiceReachesStreamingShellAndSubprocessWithoutGlobalSwitch() async {
        let previous = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
        let saved = UserDefaults.standard.string(forKey: PhoneTools.preference)
        defer {
            if let previous { setenv("DEVELOPER_DIR", previous, 1) } else { unsetenv("DEVELOPER_DIR") }
            if let saved { UserDefaults.standard.set(saved, forKey: PhoneTools.preference) }
            else { UserDefaults.standard.removeObject(forKey: PhoneTools.preference) }
        }
        let globalBefore = await Subprocess.run("/usr/bin/env", ["-u", "DEVELOPER_DIR", "/usr/bin/xcode-select", "-p"])
        PhoneTools.use(developer)
        expectEqual(ProcessInfo.processInfo.environment["DEVELOPER_DIR"], developer)
        let child = await Subprocess.run("/usr/bin/printenv", ["DEVELOPER_DIR"])
        expectEqual(child.output.trimmingCharacters(in: .whitespacesAndNewlines), developer)
        var lines = [String]()
        let status = await Shell.run("/usr/bin/printenv DEVELOPER_DIR", cwd: FileManager.default.temporaryDirectory) { lines.append($0) }
        expectEqual(status, 0)
        expectEqual(lines, [developer])
        let globalAfter = await Subprocess.run("/usr/bin/env", ["-u", "DEVELOPER_DIR", "/usr/bin/xcode-select", "-p"])
        expectEqual(globalBefore.output, globalAfter.output)
        expectEqual(globalBefore.status, globalAfter.status)
    }


    func testLegacyDiscoveryIncludesOnlyOldPhysicalIOSDevices() {
        let listing = #"[{"identifier":"old","name":"Test iPad","modelCode":"iPad6,3","platform":"com.apple.platform.iphoneos","simulator":false,"operatingSystemVersion":"16.7.10 (20H350)"},{"identifier":"new","platform":"com.apple.platform.iphoneos","simulator":false,"operatingSystemVersion":"17.0"},{"identifier":"sim","platform":"com.apple.platform.iphoneos","simulator":true,"operatingSystemVersion":"16.0"},{"identifier":"mac","platform":"com.apple.platform.macosx","simulator":false,"operatingSystemVersion":"14.0"}]"#
        let old = PhoneTools.olderPhones(listing: listing)
        expectEqual(old.map(\.id), ["old"])
        expectEqual(old.first?.family, .ipad)
        expectEqual(old.first?.version, "16.7.10")
        var p = probe(phoneVersion: nil)
        let run = p.run
        p.run = { tool, args, env in args.contains("xcdevice") ? self.result(listing) : run(tool, args, env) }
        let report = PhoneTools.check(phone: "old", probe: p)
        expectEqual(report.issue?.action, .updatePhone)
        expectTrue(report.issue?.message.contains("Test iPad") == true)
        expectTrue(PhoneTools.olderPhones(listing: "bad JSON").isEmpty)
    }


    func testOldXcodeCanTrySimulatorButNeedsUpdatingForPhone() {
        var p = probe()
        p.xcodeVersion = { _ in "15.4" }
        expectTrue(PhoneTools.check(probe: p).ready)
        expectEqual(PhoneTools.check(phone: "phone", probe: p).issue?.title, "Update Xcode")
        p.xcodeVersion = { _ in "16.0" }
        expectTrue(PhoneTools.check(phone: "phone", probe: p).ready)
    }

}


private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs == rhs, "Expected \(lhs) to equal \(rhs)", file: file, line: line)
}
private func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
private func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(!value, "Expected false", file: file, line: line)
}
