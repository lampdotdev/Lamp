import Foundation

/// Phone builds need the full Xcode app. Keep the choice inside Lamp's process: its shells, all three
/// agents, simctl and devicectl inherit it, without changing xcode-select for anything else on the Mac.
enum PhoneTools {
    static let minimumIOS = 17
    static let preference = "phoneDeveloperDirectory"
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cached: [DeviceFamily: (developer: String?, date: Date, report: Report)] = [:]

    /// Store's synchronous creation guard immediately follows the UI preflight. Reuse that result so it
    /// doesn't run the same Xcode commands again on the main thread. Explicit rechecks never use the cache.
    static func checked(family: DeviceFamily = .iphone, phone: String? = nil, useCache: Bool = false) -> Report {
        let active = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
        if useCache, phone == nil, let previous = cacheLock.withLock({ cached[family] }),
           previous.developer == active, Date().timeIntervalSince(previous.date) < 10 {
            return previous.report
        }
        let report = check(family: family, phone: phone)
        if phone == nil { cacheLock.withLock { cached[family] = (active, Date(), report) } }
        return report
    }

    enum Step: CaseIterable { case xcode, tools, firstLaunch, platform, runtime, simulator, account, phone }

    enum Action { case installXcode, useXcode, openXcode, components, simulator, settings, updatePhone, retry }
    /// The message names the setup window's buttons, so each one says them exactly as `button` does.
    struct Issue {
        let step: Step
        let title: String
        let message: String
        let action: Action
        var button: String {
            switch action {
            case .installXcode: return "Open App Store"
            case .useXcode: return "Use Xcode"
            case .openXcode: return "Open Xcode"
            case .components: return "Open Xcode"
            case .simulator: return "Open Simulator"
            case .settings: return "Open Settings"
            case .updatePhone: return "How to Update"
            case .retry: return "Check Again"
            }
        }
    }
    struct Report {
        var passed: [Step] = []
        var issue: Issue?
        var developer: String?
        var ready: Bool { issue == nil }
    }

    /// Inputs are replaceable in the standalone check harness; production always uses Apple's tools.
    struct Probe {
        var developer: () -> String? = discover
        var active: () -> String? = { ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ??
            Subprocess.runBlocking("/usr/bin/xcode-select", ["-p"], mergeErrors: false, timeout: 10).output
                .trimmingCharacters(in: .whitespacesAndNewlines) }
        var run: (String, [String], [String: String]) -> Subprocess.Result = {
            Subprocess.runBlocking($0, $1, env: $2, mergeErrors: false, timeout: 30)
        }
        var read: (URL) -> Data? = { try? Data(contentsOf: $0) }
        var xcodeVersion: (String) -> String? = { developer in
            let app = URL(fileURLWithPath: developer).deletingLastPathComponent().deletingLastPathComponent()
            return NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
        }
        var hasViewer: (String) -> Bool = { viewer(in: $0) != nil }
        var teams: () -> [(id: String, name: String)] = xcodeTeams
        var team: () -> String = { (UserDefaults.standard.string(forKey: teamPreference) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        var chooseTeam: (String) -> Void = { UserDefaults.standard.set($0, forKey: teamPreference) }

        /// Apple's tools as a new Mac has them, step by step (`Pretend`): each answers as it would before
        /// the step is done, then as this Mac's own Xcode does.
        static var pretending: Probe {
            let real = Probe()
            var probe = real
            func failed(_ errors: String = "") -> Subprocess.Result { Subprocess.Result(status: 1, output: "", errors: errors, timedOut: false) }
            func answer(_ output: String) -> Subprocess.Result { Subprocess.Result(status: 0, output: output, errors: "", timedOut: false) }
            probe.active = { Pretend.xcodeMissing("tools") ? "/Library/Developer/CommandLineTools" : real.active() }
            probe.run = { tool, arguments, env in
                if arguments == ["-checkFirstLaunchStatus"], Pretend.xcodeMissing("firstLaunch") {
                    return failed("You have not agreed to the Xcode license agreements.")
                }
                if arguments.contains("--show-sdk-path"), Pretend.xcodeMissing("platform") { return failed() }
                if arguments.starts(with: ["simctl", "list", "runtimes"]), Pretend.xcodeMissing("runtime") {
                    return answer(#"{"runtimes": []}"#)
                }
                if arguments.starts(with: ["simctl", "list", "devices"]), Pretend.xcodeMissing("simulator") {
                    return answer(#"{"devices": {}}"#)
                }
                return real.run(tool, arguments, env)
            }
            return probe
        }
    }

    /// The app that puts simulators on the Mac's screen, in this Xcode: Simulator, or Device Hub, which took
    /// its place in Xcode 27 (`Simulator.viewer`).
    static func viewer(in developer: String) -> URL? {
        let xcode = URL(fileURLWithPath: developer).deletingLastPathComponent()
        return [URL(fileURLWithPath: developer + "/Applications/Simulator.app"), xcode.appendingPathComponent("Applications/DeviceHub.app")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The team phone builds are signed for, as Settings → Building keeps it (`Devices.team`).
    static let teamPreference = "appleTeam"

    /// The teams of the accounts signed in to Xcode: the ones its automatic signing can sign for.
    static func xcodeTeams() -> [(id: String, name: String)] {
        let accounts = UserDefaults(suiteName: "com.apple.dt.Xcode")?.dictionary(forKey: "IDEProvisioningTeamByIdentifier") ?? [:]
        var teams: [(id: String, name: String)] = []
        for case let list as [[String: Any]] in accounts.values {
            for team in list {
                guard let id = team["teamID"] as? String, id.count == 10, !teams.contains(where: { $0.id == id }) else { continue }
                teams.append((id, team["teamName"] as? String ?? id))
            }
        }
        return teams.sorted { $0.name < $1.name }
    }

    static func isXcode(_ developer: String) -> Bool {
        let app = URL(fileURLWithPath: developer).deletingLastPathComponent().deletingLastPathComponent()
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        return info?["CFBundleIdentifier"] as? String == "com.apple.dt.Xcode"
            && FileManager.default.isExecutableFile(atPath: developer + "/usr/bin/xcodebuild")
    }

    static func discover() -> String? {
        if Pretend.xcodeMissing("xcode") { return nil }
        let fm = FileManager.default
        let saved = UserDefaults.standard.string(forKey: preference)
        let inherited = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
        let selected = Subprocess.runBlocking("/usr/bin/xcode-select", ["-p"], mergeErrors: false, timeout: 10)
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = [saved, inherited, selected, "/Applications/Xcode.app/Contents/Developer"].compactMap { $0 }
        for folder in ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path] {
            let apps = (try? fm.contentsOfDirectory(atPath: folder)) ?? []
            candidates += apps.sorted().filter { $0.hasSuffix(".app") }.map { folder + "/" + $0 + "/Contents/Developer" }
        }
        return candidates.first(where: isXcode)
    }

    static func use(_ developer: String) {
        UserDefaults.standard.set(developer, forKey: preference)
        setenv("DEVELOPER_DIR", developer, 1)
    }

    static func restoreChoice() {
        if !Pretend.isMissing("xcode"), let saved = UserDefaults.standard.string(forKey: preference), isXcode(saved) {
            setenv("DEVELOPER_DIR", saved, 1)
        }
    }

    struct OlderPhone: Identifiable {
        let id: String
        let name: String
        let version: String
        let family: DeviceFamily
    }

    /// CoreDevice can omit pre-iOS-17 phones. Xcode's older device listing can still identify them;
    /// show an update action rather than trying to pair or install on an unsupported phone.
    static func olderPhones() async -> [OlderPhone] {
        guard let developer = discover() else { return [] }
        let result = await Subprocess.run("/usr/bin/xcrun", ["xcdevice", "list", "--timeout", "5"],
                                          env: ["DEVELOPER_DIR": developer], mergeErrors: false, timeout: 30)
        return result.ok ? olderPhones(listing: result.output) : []
    }

    static func olderPhones(listing: String) -> [OlderPhone] {
        guard let data = listing.data(using: .utf8),
              let devices = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return devices.compactMap { device in
            guard device["simulator"] as? Bool == false,
                  device["platform"] as? String == "com.apple.platform.iphoneos",
                  let id = device["identifier"] as? String,
                  let version = device["operatingSystemVersion"] as? String,
                  major(version) > 0, major(version) < minimumIOS else { return nil }
            let name = device["name"] as? String ?? "iPhone or iPad"
            let model = device["modelCode"] as? String ?? ""
            return OlderPhone(id: id, name: name, version: String(version.split(separator: " ").first ?? ""),
                              family: model.hasPrefix("iPad") ? .ipad : .iphone)
        }.sorted { $0.name < $1.name }
    }

    private static func updateIssue(name: String, version: String) -> Issue {
        Issue(step: .phone, title: "Update your iPhone or iPad",
              message: "\(name) is on iOS \(version), and the apps Lamp makes need iOS \(minimumIOS) or later. On it, open Settings → General → Software Update. If iOS \(minimumIOS) isn't offered there, it's too old for these apps: use a newer iPhone or iPad, or try your app in the simulator.", action: .updatePhone)
    }

    /// Stop at the first failed check: later commands often fail only because an earlier step is missing.
    /// A simulator is needed even for a real phone, because that's where Lamp's agent tries the app.
    static func check(family: DeviceFamily = .iphone, phone: String? = nil, probe: Probe = Pretend.isMissing("xcode") ? .pretending : Probe()) -> Report {
        var report = Report()
        func stop(_ step: Step, _ title: String, _ message: String, _ action: Action) -> Report {
            report.issue = Issue(step: step, title: title, message: message, action: action)
            return report
        }
        guard let developer = probe.developer() else {
            return stop(.xcode, "Install Xcode", "Lamp makes iPhone and iPad apps with Xcode, and it isn't on this Mac yet. Click Open App Store and download it from there. It's free, and it's big, so it can take a while. Come back to Lamp when it has finished.", .installXcode)
        }
        report.developer = developer
        // The phone project Lamp writes uses Xcode 16's project format; older Xcode can still try apps
        // in the simulator, but must be updated before building for a physical phone.
        if phone != nil, let version = probe.xcodeVersion(developer), major(version) > 0, major(version) < 16 {
            return stop(.xcode, "Update Xcode", "Putting an app on your own iPhone or iPad needs a newer Xcode than the one on this Mac. Click Open App Store and update Xcode there. Come back to Lamp when it has finished.", .installXcode)
        }
        report.passed.append(.xcode)
        guard probe.active() == developer else {
            return stop(.tools, "Let Lamp use Xcode", "Xcode is on this Mac, and Lamp needs your go-ahead to make iPhone and iPad apps with it. Click Use Xcode. Nothing else on your Mac changes.", .useXcode)
        }
        report.passed.append(.tools)
        let env = ["DEVELOPER_DIR": developer]
        let xcodebuild = developer + "/usr/bin/xcodebuild"
        let first = probe.run(xcodebuild, ["-checkFirstLaunchStatus"], env)
        guard first.ok else {
            if first.timedOut || first.status == -1 {
                return stop(.firstLaunch, "Xcode isn't responding", "Lamp asked Xcode whether it's ready and got no answer. Click Open Xcode and wait for its window to appear, then come back to Lamp.", .openXcode)
            }
            let license = (first.output + first.errors).lowercased().contains("license")
            return stop(.firstLaunch, license ? "Accept Xcode's agreements" : "Finish Xcode setup",
                        license ? "Xcode won't make anything until you agree to Apple's terms. Click Open Xcode and agree when it asks. If it then offers to install more, let it. Come back to Lamp when it has finished."
                        : "Xcode has a few things to set up the first time it opens. Click Open Xcode and say yes to what it asks to install. Come back to Lamp when it has finished.", .openXcode)
        }
        report.passed.append(.firstLaunch)
        for sdk in ["iphoneos", "iphonesimulator"] {
            guard probe.run("/usr/bin/xcrun", ["--sdk", sdk, "--show-sdk-path"], env).ok else {
                return stop(.platform, "Add iOS to Xcode", "Xcode needs one more download before it can make iPhone and iPad apps. Click Open Xcode, choose Xcode → Settings from the menu bar, then click Components (Platforms in older versions of Xcode) and click Get beside iOS. Come back to Lamp when the download finishes.", .components)
            }
        }
        report.passed.append(.platform)
        let runtimes = probe.run("/usr/bin/xcrun", ["simctl", "list", "runtimes", "-j"], env)
        guard runtimes.ok, let data = runtimes.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["runtimes"] as? [[String: Any]] else {
            return stop(.runtime, "The simulator isn't responding", "The simulator is the iPhone or iPad that appears on your Mac's screen, and Lamp got no answer from it. Click Open Xcode and wait for its window to appear. If the Simulator app is open, quit it. Then come back to Lamp.", .openXcode)
        }
        guard list.contains(where: { runtime in
            (runtime["identifier"] as? String ?? "").contains("SimRuntime.iOS-")
                && major(runtime["version"] as? String) >= minimumIOS && runtime["isAvailable"] as? Bool == true
        }) else {
            return stop(.runtime, "Download iOS for the simulator", "Lamp tries your app in a simulator, an iPhone or iPad that appears on your Mac's screen, and that needs iOS \(minimumIOS) or later. Click Open Xcode, choose Xcode → Settings from the menu bar, then click Components (Platforms in older versions of Xcode) and click Get beside the newest iOS. Come back to Lamp when the download finishes.", .components)
        }
        report.passed.append(.runtime)
        let devices = probe.run("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "-j"], env)
        guard devices.ok, Simulator.device(family, listing: devices.output) != nil else {
            return stop(.simulator, "Add an \(family.name) simulator", "There's no \(family.name) for Lamp to try your app on yet. Click Open Simulator, then choose File → New Simulator from the menu bar. Pick any \(family.name) with iOS \(minimumIOS) or later, click Create, and come back to Lamp.", .simulator)
        }
        // The devices are run by a service and shown by an app (Simulator, or Device Hub in Xcode 27): an Xcode
        // without it would run the app on a screen nobody can see.
        guard probe.hasViewer(developer) else {
            return stop(.simulator, "Finish installing Xcode", "The simulator is the iPhone or iPad that appears on your Mac's screen, and the Xcode on this Mac is missing the app that shows it. Click Open Xcode, choose Xcode → Settings from the menu bar, then click Components and make sure iOS and its simulator are installed. If they are, reinstall Xcode from the App Store. Come back to Lamp when it has finished.", .components)
        }
        report.passed.append(.simulator)
        if let phone {
            // Xcode signs the app for the phone with an account signed in to it, for the team chosen in
            // Settings → Building; without those the build would only fail later, after the phone is paired.
            // One signed-in team is chosen by itself, as Settings does.
            let teams = probe.teams()
            guard !teams.isEmpty else {
                return stop(.account, "Sign in to Xcode", "Putting an app on your own iPhone or iPad needs an Apple Account signed in to Xcode; a free one will do. Click Open Xcode, choose Xcode → Settings from the menu bar, click Accounts, then click + and sign in. Come back to Lamp and click Check Again.", .openXcode)
            }
            if !teams.contains(where: { $0.id == probe.team() }) {
                guard teams.count == 1 else {
                    return stop(.account, "Choose your Apple team", "Xcode is signed in with more than one team, and Lamp needs to know which one signs apps for your phone. Click Open Settings and choose it under Building, then click Check Again.", .settings)
                }
                probe.chooseTeam(teams[0].id)
            }
            report.passed.append(.account)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-phone-version-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: file) }
            let result = probe.run("/usr/bin/xcrun", ["devicectl", "list", "devices", "--timeout", "5", "--json-output", file.path], env)
            guard result.ok, let data = probe.read(file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let devices = (json["result"] as? [String: Any])?["devices"] as? [[String: Any]],
                  let device = devices.first(where: { ($0["hardwareProperties"] as? [String: Any])?["udid"] as? String == phone }),
                  let properties = device["deviceProperties"] as? [String: Any],
                  let version = properties["osVersionNumber"] as? String, major(version) > 0 else {
                let legacy = probe.run("/usr/bin/xcrun", ["xcdevice", "list", "--timeout", "5"], env)
                if legacy.ok, let old = olderPhones(listing: legacy.output).first(where: { $0.id == phone }) {
                    report.issue = updateIssue(name: old.name, version: old.version)
                    return report
                }
                return stop(.phone, "Plug in your iPhone or iPad", "Lamp couldn't reach it to see which iOS it has. Connect it to this Mac with its cable, unlock it, then click Check Again.", .retry)
            }
            guard major(version) >= minimumIOS else {
                let name = properties["name"] as? String ?? "This phone"
                report.issue = updateIssue(name: name, version: version)
                return report
            }
            report.passed.append(.phone)
        }
        return report
    }

    private static func major(_ version: String?) -> Int { Int((version ?? "").split(separator: ".").first ?? "") ?? 0 }
}
