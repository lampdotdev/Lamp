import Foundation

/// Screens: a TV app (`Platform.tv`) given places beside the TV (`LampProject.places`), for something shown full screen
/// and glanced at from across a room: a family calendar, a photo album, a dashboard, a scoreboard, a clock. It's the TV
/// app's page in `Web/` and its `Web/lamp.js` (`TVTemplate`: LampAI, LampStore and LampAssets for the web, a remote's
/// keys, focus moved with the arrows), laid out at 1920x1080, shown wherever it's been put.
///
/// On this Mac, an iPhone or an iPad it's an app with a little Swift of Lamp's own around the page (`LampScreen.swift`,
/// `LampPage.swift` and LampSupport.swift, so a Mac copy has the wand and the chat beside it), which zooms the page to
/// the window and answers its LampAI and `LampNative` calls for it. On a Samsung or LG TV it's the TV app it always was,
/// and on the Xbox the integration's web app ("xbox-one"), each reaching Lamp as a TV app does.
///
/// Wherever it's shown, the agent looks at it in the TV preview on the Mac, the same page at the same size with a
/// remote's keys, so it never waits for a build of the Mac app to see a change.
enum ScreenKit {
    /// A TV app, whatever its places: every one is a screen, the TV its only place until it's given others.
    static func isScreen(_ project: LampProject) -> Bool { project.platform == .tv }

    /// Shown on this Mac or an iPhone or iPad, so it has the app around the page, which a TV app alone doesn't.
    static func hostsOnApple(_ project: LampProject) -> Bool {
        isScreen(project) && !project.isPart && (project.openPlaces.contains(.mac) || project.openPlaces.contains(.ios))
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static var host: String? {
        Bundle.main.resourceURL.flatMap { try? String(contentsOf: $0.appendingPathComponent("GameKit/apple/LampScreen.swift"), encoding: .utf8) }
    }

    /// The files Lamp writes for the app around the page.
    static let hostPaths = ["Sources/LampScreen.swift", "Sources/LampPage.swift", "Sources/LampSupport.swift", "build.sh", "Package.swift"]

    /// Lamp's own files, written before every turn and build: the page's script, and where it's shown on Apple's
    /// devices the Swift around it and what builds it; where it's no longer shown there, those go.
    static func write(for project: LampProject) throws {
        try TVTemplate.writeOwnedFiles(for: project)
        guard hostsOnApple(project) else {
            if FileManager.default.fileExists(atPath: project.dir.appendingPathComponent(hostPaths[0]).path) { remove(from: project) }
            return
        }
        guard let host else { throw Failure(message: "This copy of Lamp is missing its screen kit.") }
        try Template.write(host, to: "Sources/LampScreen.swift", for: project)
        try GameKit.writePage(for: project)
        try Template.put(Template.lampSupportSwift(for: project), at: project.dir.appendingPathComponent("Sources/LampSupport.swift"), for: project)
        try Template.write(GameKit.webBuildSh, to: "build.sh", for: project, executable: true)
        try Template.write(packageSwift, to: "Package.swift", for: project)
        let ignore = project.dir.appendingPathComponent(".gitignore")
        if let kept = AppFile.read(ignore, in: project).map({ String(decoding: $0, as: UTF8.self) }), !kept.contains(".build/") {
            try AppFolder.write(kept + ".build/\nbuild/\n", to: ignore, in: project.dir)
        }
    }

    /// The scaffold: the TV app's page, which already shows the app's name at a TV's size.
    static func fill(_ project: LampProject) throws {
        try TVTemplate.fill(project)
        try write(for: project)
    }

    /// Takes the app around the page away (it's shown on a TV alone now, or no longer a screen).
    static func remove(from project: LampProject) {
        for path in hostPaths { AppFolder.remove(project.dir.appendingPathComponent(path), in: project.dir) }
        GameKit.removePage(from: project)
    }

    /// Every path Lamp owns in a screen.
    static func paths(for project: LampProject) -> [String] { [TVTemplate.supportFile] + (hostsOnApple(project) ? hostPaths : []) }

    static let packageSwift = """
    // swift-tools-version:5.9
    import PackageDescription

    let package = Package(
        name: "{{EXE}}",
        platforms: [.macOS(.v14), .iOS(.v17)],
        targets: [.executableTarget(name: "{{EXE}}", path: "Sources")]
    )

    """

    /// Names what Lamp writes into a screen, so a new Lamp's builds it again (`Target.Recipe.inputs`).
    static var stamp: String { (host ?? "") + (GameKit.page?.text ?? "") + GameKit.webBuildSh + packageSwift + TVTemplate.lampJS }
}

// MARK: - What the builder is told

extension Agent {
    /// The rules for a screen: the TV app's rules for the page (it's the same page), with where it's shown in the
    /// request's device line (`Rules.screenPlaces`), since a place may be given at any time.
    static func screenPrompt(for project: LampProject) -> String {
        let rules = [Rules.screenEdit, Rules.ask, Rules.shell, Rules.tvFrameworks, Rules.tvDesign, Rules.tvKeys, Rules.tvData, Rules.webAI, Rules.pageNative,
                     Rules.webSound, Rules.icon, Rules.about, Rules.tvAttachments, Rules.tvLogs, Rules.tvTry, Rules.appMd, Rules.audience,
                     Rules.begin, Rules.finish]
        return (Rules.screenHeader + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: "screen")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a screen")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "opens it again in the TV preview")
    }
}

extension Agent.Rules {
    static let screenHeader = """
    You are Lamp's builder agent. The current directory is a screen: a page (HTML, CSS and JavaScript in Web/) shown \
    full screen and glanced at from across a room, the same page wherever it's shown. Its home is the person's Mac, \
    where it's an app in its own window; it's shown on an iPhone or iPad, a Samsung or LG TV and the person's Xbox too \
    once it's put there. You try it in the TV preview on this Mac, the same page at the same 1920x1080 with a remote's \
    keys. The request's device line says where it's shown: never say it's on a device it isn't on. Read APP.md first \
    for context.
    """

    static let screenEdit = """
    - Make the change the user asks for by editing the page's files in Web/ (index.html, style.css, app.js and any \
    others), and what it shows beside them, and Sources/Native.swift for what the page asks of the device. Web/lamp.js, \
    the rest of Sources/, build.sh and Package.swift are Lamp's (the page's building blocks and the app around it): read lamp.js, never edit or delete any of them. Lamp builds by itself and, \
    at the end of your turn, opens the screen where Try On points (its window on this Mac, a simulator, a TV or the \
    Xbox), so don't run a build, a server or a browser yourself, and leave .lamp/ alone. Lay the page out for a fixed \
    1920x1080, as for a TV: Lamp scales it to every screen. Where else it's shown is the person's to ask for: when they \
    want it on their iPad, TV or Xbox, call make_app_for with "screen" and every place it's to be on (["screen", \
    "mac", "ipad"], ["screen", "mac", "tv"]…); it stays the same screen.
    """

    /// Where a screen is shown, for the request's device line.
    static func screenPlaces(_ project: LampProject) -> String {
        "It's shown on \(GameKit.spoken(project.openPlaces).replacingOccurrences(of: "your ", with: "the person's ")), and Try On points at the "
            + "\(GameKit.placeName(project.destination)) now. Keep it within what a TV's browser draws smoothly: plain HTML and CSS, few animations."
    }
}
