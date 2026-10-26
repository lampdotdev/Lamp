import Foundation

/// Screens: Lamp's own kind of app (`Platform.screen`) for something shown full screen and glanced at from across a room:
/// a family calendar, a photo album, a dashboard, a scoreboard, a clock. It's a page in `Web/`, the TV app's page and
/// its `Web/lamp.js` (`TVTemplate`: LampAI, LampStore and LampAssets for the web, a remote's keys, focus moved with the
/// arrows), laid out at 1920x1080, and it's shown wherever it's been put (`LampProject.places`).
///
/// Its home is the Mac: a Mac app in the person's Apps like any other, with a little Swift of Lamp's own around the page
/// (`LampScreen.swift` and LampSupport.swift, so it has the wand and the chat beside it), which zooms the page to the
/// window and answers its LampAI calls for it (the `lampGateway` bridge, with the app's own token). The same app goes on
/// an iPhone or iPad. On a Samsung or LG TV it's the TV app's own way there (`TVs`), and on the Xbox the integration's
/// web app ("xbox-one"), each reaching Lamp as a TV app does.
///
/// Wherever it's shown, the agent looks at it in the TV preview on the Mac, the same page at the same size with a
/// remote's keys, so it never waits for a build of the Mac app to see a change.
enum ScreenKit {
    /// What marks a screen's folder, kept with the code so a version restored brings the kind back with it.
    static let marker = ".lamp-screen"

    static func isScreen(_ project: LampProject) -> Bool { project.platform == .screen }

    /// Shown on this Mac or an iPhone or iPad, where it's an app of Lamp's around the page.
    static func hostsOnApple(_ project: LampProject) -> Bool {
        isScreen(project) && (project.openPlaces.contains(.mac) || project.openPlaces.contains(.ios))
    }

    static func isMade(_ dir: URL) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path) }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static var host: String? {
        Bundle.main.resourceURL.flatMap { try? String(contentsOf: $0.appendingPathComponent("GameKit/apple/LampScreen.swift"), encoding: .utf8) }
    }

    /// Lamp's own files, written before every turn and build: the page's script, the Swift around it, what builds it.
    static func write(for project: LampProject) throws {
        guard let host else { throw Failure(message: "This copy of Lamp is missing its screen kit.") }
        try TVTemplate.writeOwnedFiles(for: project)
        try Template.write(host, to: "Sources/LampScreen.swift", for: project)
        try GameKit.writePage(for: project)
        try Template.put(Template.lampSupportSwift(for: project), at: project.dir.appendingPathComponent("Sources/LampSupport.swift"), for: project)
        try Template.write(GameKit.webBuildSh, to: "build.sh", for: project, executable: true)
        try Template.write(packageSwift, to: "Package.swift", for: project)
        try Template.write("A screen made with Lamp: a page in Web/, shown full screen.\n", to: marker, for: project)
    }

    /// The scaffold: the TV app's page, which already shows the app's name at a TV's size.
    static func fill(_ project: LampProject) throws {
        try Template.write(TVTemplate.indexHTML, to: "Web/index.html", for: project)
        try Template.write(TVTemplate.styleCSS, to: "Web/style.css", for: project)
        try Template.write(TVTemplate.appJS, to: "Web/app.js", for: project)
        try Template.write(appMd, to: "APP.md", for: project)
        try Template.write(".lamp/\n.build/\nbuild/\n", to: ".gitignore", for: project)
        try write(for: project)
    }

    static func remove(from project: LampProject) {
        for path in ["Sources/LampScreen.swift", marker] { AppFolder.remove(project.dir.appendingPathComponent(path), in: project.dir) }
        GameKit.removePage(from: project)
    }

    /// Every path Lamp owns in a screen.
    static let paths = [TVTemplate.supportFile, "Sources/LampScreen.swift", "Sources/LampPage.swift", "Sources/LampSupport.swift", "build.sh", "Package.swift", marker]

    static let appMd = """
    # {{NAME}}

    A screen built and changed with Lamp: a page in Web/ (HTML, CSS and JavaScript) shown full screen and glanced at from
    across a room. It's a Mac app shown in its own window, and goes on an iPhone, an iPad, a Samsung or LG TV or an Xbox
    too once it's put there. Lamp looks at it in its TV preview on the Mac.

    ## What it does
    Nothing yet: fresh scaffold.

    """

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

    /// The rules for a screen that's one of a wish's apps, in a folder of its own: the screen's own, for the files
    /// there, without those about the wish as a whole.
    static func screenPrompt(part folder: String, alone: Bool = false) -> String {
        let rules = [Rules.screenEdit, Rules.tvFrameworks, Rules.tvDesign, Rules.tvKeys, Rules.tvData, Rules.webAI, Rules.pageNative,
                     Rules.webSound, Rules.tvLogs, Rules.tvTry, alone ? "" : Rules.screenAmongApps + Rules.wishTalk]
        return (Rules.partHeader("a screen, a page in Web/ shown full screen and glanced at from across a room, at home on the Mac and shown on an iPhone or iPad, a TV and an Xbox too once it's put there", folder: folder)
                + "\n\nRules:\n" + rules.joined())
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
    want it on their iPad, TV or Xbox, call make_app_for with `devices` every device it's to be on ("mac", "ipad", \
    "tv"…) and `made` "web"; it stays the same screen, and the wish's other apps stay as they are.
    """

    /// Where a screen is shown, for the request's device line.
    static func screenPlaces(_ project: LampProject) -> String {
        "It's shown on \(GameKit.spoken(project.openPlaces).replacingOccurrences(of: "your ", with: "the person's ")), and Try On points at the "
            + "\(GameKit.placeName(project.destination)) now. Keep it within what a TV's browser draws smoothly: plain HTML and CSS, few animations."
    }
}
