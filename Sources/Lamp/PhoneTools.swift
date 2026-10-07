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

    enum Step: String, CaseIterable {
        case xcode = "Xcode installed"
        case tools = "Lamp using Xcode"
        case firstLaunch = "Xcode setup finished"
        case platform = "iOS building tools installed"
        case runtime = "iOS simulator installed"
        case simulator = "Simulator ready"
        case phone = "Phone software supported"
    }

    enum Action { case installXcode, useXcode, openXcode, components, simulator, updatePhone, retry }
    struct Issue {
        let step: Step
        let title: String
        let message: String
        let action: Action
        var button: String {
            switch action {
            case .installXcode: return "Get Xcode"
            case .useXcode: return "Use Xcode in Lamp"
            case .openXcode: return "Open Xcode"
            case .components: return "Open Xcode"
            case .simulator: return "Open Simulator"
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
    }

    static func isXcode(_ developer: String) -> Bool {
        let app = URL(fileURLWithPath: developer).deletingLastPathComponent().deletingLastPathComponent()
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        return info?["CFBundleIdentifier"] as? String == "com.apple.dt.Xcode"
            && FileManager.default.isExecutableFile(atPath: developer + "/usr/bin/xcodebuild")
    }

    static func discover() -> String? {
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
        if let saved = UserDefaults.standard.string(forKey: preference), isXcode(saved) {
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
        Issue(step: .phone, title: "Update your phone",
              message: "\(name) has iOS \(version). Lamp's apps need iOS \(minimumIOS) or later. On the phone, open Settings → General → Software Update. If it can't update to iOS \(minimumIOS), use a newer iPhone or iPad, or try your app in the simulator.", action: .updatePhone)
    }

    /// Stop at the first failed check: later commands often fail only because an earlier step is missing.
    /// A simulator is needed even for a real phone, because that's where Lamp's agent tries the app.
    static func check(family: DeviceFamily = .iphone, phone: String? = nil, probe: Probe = Probe()) -> Report {
        var report = Report()
        func stop(_ step: Step, _ title: String, _ message: String, _ action: Action) -> Report {
            report.issue = Issue(step: step, title: title, message: message, action: action)
            return report
        }
        guard let developer = probe.developer() else {
            return stop(.xcode, "Install Xcode", "iPhone and iPad apps need Apple's full Xcode app. Install it from the Mac App Store, then come back to Lamp.", .installXcode)
        }
        report.developer = developer
        // The phone project Lamp writes uses Xcode 16's project format; older Xcode can still try apps
        // in the simulator, but must be updated before building for a physical phone.
        if phone != nil, let version = probe.xcodeVersion(developer), major(version) > 0, major(version) < 16 {
            return stop(.xcode, "Update Xcode", "Putting Lamp's apps on a phone needs Xcode 16 or later. Update Xcode in the Mac App Store, then come back to Lamp.", .installXcode)
        }
        report.passed.append(.xcode)
        guard probe.active() == developer else {
            return stop(.tools, "Let Lamp use Xcode", "This Mac's selected tools don't include everything needed for iPhone apps. Lamp can use Xcode for its own work. Your Mac's tools setting stays as it is.", .useXcode)
        }
        report.passed.append(.tools)
        let env = ["DEVELOPER_DIR": developer]
        let xcodebuild = developer + "/usr/bin/xcodebuild"
        let first = probe.run(xcodebuild, ["-checkFirstLaunchStatus"], env)
        guard first.ok else {
            if first.timedOut || first.status == -1 {
                return stop(.firstLaunch, "Xcode isn't responding", "Open Xcode and let it finish starting, then come back and check again.", .openXcode)
            }
            let license = (first.output + first.errors).lowercased().contains("license")
            return stop(.firstLaunch, license ? "Accept Xcode's agreements" : "Finish Xcode setup",
                        license ? "Open Xcode and read and accept Apple's agreements, then let it install anything it asks for. Come back to Lamp when it's finished."
                        : "Open Xcode and finish its welcome steps, including any agreements and additional tools it asks to install. Come back to Lamp when it's finished.", .openXcode)
        }
        report.passed.append(.firstLaunch)
        for sdk in ["iphoneos", "iphonesimulator"] {
            guard probe.run("/usr/bin/xcrun", ["--sdk", sdk, "--show-sdk-path"], env).ok else {
                return stop(.platform, "Add iOS to Xcode", "In Xcode, open Settings → Components and install iOS. In older Xcode versions, this is called Platforms. Come back to Lamp when the download finishes.", .components)
            }
        }
        report.passed.append(.platform)
        let runtimes = probe.run("/usr/bin/xcrun", ["simctl", "list", "runtimes", "-j"], env)
        guard runtimes.ok, let data = runtimes.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["runtimes"] as? [[String: Any]] else {
            return stop(.runtime, "The simulator isn't responding", "Open Xcode and let it finish starting. If Simulator is open, quit it. Then come back and check again.", .openXcode)
        }
        guard list.contains(where: { runtime in
            (runtime["identifier"] as? String ?? "").contains("SimRuntime.iOS-")
                && major(runtime["version"] as? String) >= minimumIOS && runtime["isAvailable"] as? Bool == true
        }) else {
            return stop(.runtime, "Download an iOS simulator", "In Xcode, open Settings → Components and download an iOS \(minimumIOS) or later simulator. In older Xcode versions, this is called Platforms. Lamp uses it to try your app before it goes on your phone.", .components)
        }
        report.passed.append(.runtime)
        let devices = probe.run("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "-j"], env)
        guard devices.ok, Simulator.device(family, listing: devices.output) != nil else {
            return stop(.simulator, "Add an \(family.name) simulator", "Open Simulator, then choose File → New Simulator. Choose an \(family.name) and an iOS \(minimumIOS) or later version, then come back to Lamp.", .simulator)
        }
        report.passed.append(.simulator)
        if let phone {
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
                return stop(.phone, "Check the phone's software", "Plug the chosen phone into this Mac and unlock it, then check again so Lamp can read its software version.", .retry)
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
