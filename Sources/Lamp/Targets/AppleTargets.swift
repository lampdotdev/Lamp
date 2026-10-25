import Foundation

extension Platform {
    /// A Mac app that installs beside the person's others.
    static let mac = Platform(kind: "mac")
    /// The iOS kind: iPhone and iPad apps alike (`DeviceFamily`), in the iOS Simulator or on the person's own phone.
    static let iphone = Platform(kind: "iphone")
    /// One app for the Mac and the iPhone, as Xcode's multiplatform apps are: one code, built for where Try On points.
    static let universal = Platform(kind: "universal")
}

/// Lamp's Swift kinds: one Swift Package each, whose platforms say which it is, and one family as a wish's part, since
/// a part made for more of Apple's devices is changed in place.
extension Target {
    static let mac = Target(
        platform: .mac, places: [.mac],
        identity: Identity(name: "the Mac app", phrase: "a Mac app", analytics: "mac", made: { _, _ in "the Mac" },
                           devices: Words(words: [("mac", "\"mac\" for this Mac", "\"mac\" for this Mac")], hint: "[\"mac\"] otherwise",
                                            claims: { $0 == ["mac"] }, alone: false, asked: ("mac", "for this Mac", "for this Mac")),
                           tryOnHelp: { _ in "" }, place: { _ in nil }),
        guidance: Guidance(prompt: { _ in Agent.systemPrompt }, changeRules: { _ in Agent.Rules.macFrameworks },
                           skills: { ["app-kinds", "menu-bar", "mac-widgets"] + (Agent.Rules.scenes ? ["scene-3d", "maps"] : []) },
                           named: Skills.swiftNamed + ["finder-files"],
                           elsewhere: { _ in nil }),
        recipe: .swift(.mac, app: Template.appSwift, view: Template.contentViewSwift, md: Template.appMd) { project, widget, share in
            try Template.write(Template.withScene(Template.buildSh(widget: widget, share: share, widgetOnly: Template.isWidgetOnly(project)), for: project),
                               to: "build.sh", for: project, executable: true)
            try Template.write(Template.withScene(Template.packageSwift(widget: widget, share: share), for: project), to: "Package.swift", for: project)
        },
        part: .swift(.mac, folder: "Mac", word: "mac", menu: ("Mac App", "laptopcomputer")) {
            Agent.prompt(platform: .mac, device: "Mac", sidebar: false, part: $0, alone: $1)
        },
        setup: .none)

    static let iphone = Target(
        platform: .iphone, places: [.ios],
        identity: Identity(name: "the iPhone app", phrase: "an iPhone and iPad app", analytics: "iphone", made: { _, _ in "iPhone and iPad" },
                           devices: Words(words: [("iphone", "\"iphone\" for iPhone and iPad", "\"iphone\" for iPhone and iPad"),
                                                    ("watch", "\"watch\" for an Apple Watch app, which comes with the iPhone app",
                                                     "\"watch\" for Apple Watch (with \"iphone\", when they mention a watch or their wrist)")],
                                            hint: "[\"iphone\"] when they mention a phone, an iPhone or iPad, or what's done away from a desk (out walking or running, the camera on the go, tilting or shaking it)",
                                            claims: { !$0.isEmpty && $0.isSubset(of: ["iphone", "watch"]) }, alone: false,
                                            asked: ("iphone", "for iPhone and iPad", "for iPhone and iPad")),
                           tryOnHelp: { _ in "Where it opens: a simulator, or your own iPhone or iPad" },
                           place: { Template.hasWatch($0) ? .iPhoneAndWatch : .iPhone }),
        guidance: Guidance(prompt: { Agent.iPhonePrompt(for: $0.family) }, changeRules: { _ in Agent.Rules.iPhoneFrameworks + Agent.Rules.iPhoneTry },
                           skills: { ["app-kinds", "iphone-hardware", "iphone-widgets", "apple-watch"] }, named: Skills.swiftNamed + ["icloud-sync"],
                           elsewhere: Guidance.phoneAway),
        recipe: .swift(.iphone, app: Template.iPhoneAppSwift, view: Template.iPhoneContentViewSwift, md: Template.iPhoneAppMd) { project, widget, share in
            try Template.write(Template.withWatch(Template.iPhoneBuildSh(widget: widget, share: share), for: project), to: "build.sh", for: project, executable: true)
            try Template.write(Template.withWatch(Template.iPhonePackageSwift(widget: widget, share: share), for: project), to: "Package.swift", for: project)
        },
        part: .swift(.iphone, folder: "iPhone", word: "iphone", menu: ("iPhone App", "iphone")) {
            Agent.prompt(platform: .iphone, device: DeviceFamily.iphone.name, sidebar: false, part: $0, alone: $1)
        },
        setup: .phone(both: false, made: "iPhone and iPad"), otherSystems: true)

    static let universal = Target(
        platform: .universal, places: [.mac, .ios],
        identity: Identity(name: "the Mac and iPhone app", phrase: "an app for the Mac and the iPhone, one code for both", analytics: "universal",
                           made: { _, _ in "the Mac, iPhone and iPad" },
                           devices: Words(words: [], hint: "[\"mac\", \"iphone\"] when they want it on their Mac and their phone, or kept the same on each",
                                            claims: { $0.contains("mac") && ($0.contains("iphone") || $0.contains("watch")) && $0.isSubset(of: ["mac", "iphone", "watch"]) },
                                            alone: false),
                           tryOnHelp: { _ in "Where it opens: this Mac, a simulator, or your own iPhone or iPad" }, place: { _ in .everywhere }),
        guidance: Guidance(prompt: { Agent.universalPrompt(for: $0.family) },
                           changeRules: { _ in Agent.Rules.universal + Agent.Rules.universalFrameworks + Agent.Rules.universalTry },
                           skills: { ["app-kinds", "menu-bar", "iphone-hardware", "iphone-widgets", "apple-watch"] },
                           named: Skills.swiftNamed + ["finder-files", "icloud-sync"], elsewhere: Guidance.phoneAway),
        recipe: .swift(.universal, app: Template.universalAppSwift, view: Template.universalContentViewSwift, md: Template.universalAppMd) { project, widget, share in
            try Template.write(Template.withWatch(Template.universalBuildSh(widget: widget, share: share), for: project), to: "build.sh", for: project, executable: true)
            try Template.write(Template.withWatch(Template.universalPackageSwift(widget: widget, share: share), for: project), to: "Package.swift", for: project)
            // The Mac build is Xcode's, from the phone's project (one project, both platforms), signed for the person's
            // team: that lets the app use what Apple ties to a team, which Lamp's own signing can't give it.
            try Template.writeDeviceProject(for: project, team: Devices.team)
        },
        part: .swift(.universal, folder: "Apple", word: "iphone", menu: ("iPhone App", "iphone")) { Agent.universalPrompt(for: .iphone, part: $0, alone: $1) },
        setup: .phone(both: true, made: "the Mac, iPhone and iPad"), otherSystems: true, macSignedForTeam: true)
}

extension Target.Recipe {
    /// A Swift Package of one of Lamp's Swift kinds, `build` writing its build.sh and Package.swift.
    static func swift(_ kind: Platform, app: String, view: String, md: String,
                      build: @escaping (LampProject, _ widget: Bool, _ share: Bool) throws -> Void) -> Self {
        Self(language: .swift,
             fill: { try Template.fillSwift($0, app: app, view: view, md: md) },
             ownedFiles: { project in try Template.writeSwiftOwnedFiles(for: project) { try build(project, $0, $1) } },
             support: Template.writeSwiftSupport,
             isMade: { dir in (try? String(contentsOf: dir.appendingPathComponent("Package.swift"), encoding: .utf8)).flatMap(swiftKind) == kind },
             scaffolded: { dir, _ in FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) },
             sources: { _ in ["Sources", Template.widgetFolder, Template.shareFolder, Template.watchFolder, "Package.swift", "icon.json", "capabilities.json"] },
             builtURL: { $0.dir.appendingPathComponent(kind.choosesPlace && $0.onIOS ? "build/iOS/\($0.exe).app" : "build/\($0.exe).app") },
             shareRefusal: nil)
    }

    /// The Swift kind a Package.swift's platforms make.
    static func swiftKind(_ package: String) -> Platform? {
        let mac = package.contains(".macOS("), ios = package.contains(".iOS(")
        return mac && ios ? .universal : ios ? .iphone : mac ? .mac : nil
    }
}

extension Target.Part {
    /// A Swift kind as a wish's part: its folder holds a Package.swift of that kind, of which at most the last 64 KB is
    /// read (Lamp's own is far smaller; one the agent made huge is never read whole).
    static func swift(_ kind: Platform, folder: String, word: String, menu: (name: String, symbol: String),
                      rules: @escaping (String, Bool) -> String) -> Self {
        Self(folder: folder, family: "apple", word: word, menu: menu, rules: rules) { dir, wish in
            AppFile.read(dir.appendingPathComponent("Package.swift"), inFolder: wish, last: 64 * 1024)
                .flatMap { Target.Recipe.swiftKind(String(decoding: $0, as: UTF8.self)) } == kind
        }
    }
}

extension Target.Guidance {
    /// What an iPhone app has of Lamp's AI on the person's phone away from this Mac.
    static let phoneAway: @MainActor (LampProject) -> String? = { project in
        let away = AppAI.resolve(.text, for: project, in: .phoneAway)
        return "- On the person's phone away from this Mac: \(away.tier == .none ? "no AI" : "text, pictures and decisions through OpenRouter")"
    }
}

extension Target.Setup {
    /// The iPhone's kinds need Xcode, and an app for both a team too: not said, a wish stays a Mac app until they're
    /// here, with Apple's setup a line away, and is then asked to be made for the iPhone.
    static func phone(both: Bool, made: String) -> Self {
        let issue = { @MainActor in
            await Task.detached { PhoneTools.checked(family: .iphone, phone: nil, requiresTeam: both, requiresPaidTeam: false) }.value.issue
        }
        return Self(canChoose: { said, _ in said ? true : await issue() == nil },
                    notReady: { _, part in
                        guard let issue = await issue() else { return nil }
                        PhoneSetup.shared.show()
                        return "this Mac can't build \(part.map { "\($0) yet" } ?? "it for \(made)"). \(issue.title): \(issue.message) Lamp opened its setup steps."
                    },
                    later: SetupLater(symbol: "iphone", needs: "a few things from Apple", apps: "iPhone apps",
                                      request: both ? "Make it work on my iPhone too." : "Make it an iPhone app instead.") { wanted, cancelled, done in
                        PhoneSetup.shared.perform(resolve: { wanted() ? PhoneSetup.Context(family: .iphone, requiresTeam: both) : nil },
                                                  cancelled: cancelled, then: done)
                    })
    }
}
