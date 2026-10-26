import Foundation

/// Screens: Lamp's own kind of app (`Platform.screen`) for something shown full screen and glanced at from across a room:
/// a family calendar, a photo album, a dashboard, a scoreboard, a clock. It's a page in `Web/` with the TV app's
/// `Web/lamp.js` (`TVTemplate`: LampAI, LampStore and LampAssets for the web, a remote's keys, focus moved with the
/// arrows), and it's shown wherever it's been put (`LampProject.places`). The page fills whatever it's shown on, as a web
/// page fills a browser: a TV, a Mac window of any size, an iPad either way up, a phone, a photo frame. A screen made
/// before that is laid out at a fixed 1920x1080 (its viewport says so, `fillsAnyShape`), and is still zoomed to fit.
///
/// Its home is the Mac: a Mac app in the person's Apps like any other, with a little Swift of Lamp's own around the page
/// (`LampScreen.swift` and LampSupport.swift, so it has the wand and the chat beside it), which zooms the page to the
/// window (`LampScreenPage.fit`) and answers its LampAI calls for it (the `lampGateway` bridge, with the app's own token). The same app goes on
/// an iPhone or iPad. On Android (a tablet, or a photo frame running Android) it's Lamp's own Android app around the
/// page, the one a three.js game has there (`GameAndroid`), kept awake and fitted to the screen. On a Samsung or LG TV it's the TV app's own way there (`TVs`), and on the Xbox the integration's
/// web app ("xbox-one"), each reaching Lamp as a TV app does.
///
/// Wherever it's shown, the agent looks at it in the TV preview on the Mac, the same page with a remote's keys, at any
/// shape it asks for (`look_at_app`'s `shape`), so it never waits for a build of the Mac app to see a change.
enum ScreenKit {
    /// What marks a screen's folder, kept with the code so a version restored brings the kind back with it.
    static let marker = ".lamp-screen"

    static func isScreen(_ project: LampProject) -> Bool { project.platform == .screen }

    /// Shown on this Mac or an iPhone or iPad, where it's an app of Lamp's around the page.
    static func hostsOnApple(_ project: LampProject) -> Bool {
        isScreen(project) && (project.openPlaces.contains(.mac) || project.openPlaces.contains(.ios))
    }

    static func isMade(_ dir: URL) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path) }

    /// Whether the page fills any shape: its viewport isn't the fixed `width=1920` screens were laid out at before.
    static func fillsAnyShape(_ project: LampProject) -> Bool {
        guard let page = try? String(contentsOf: project.dir.appendingPathComponent("Web/index.html"), encoding: .utf8) else { return true }
        return !isFixed(page)
    }

    /// A page laid out at a fixed 1920x1080: its viewport meta names that width (Lamp's TV scaffold's
    /// `width=1920, height=1080`). The app around a screen reads the same thing (`LampScreenPage.fixed`).
    static func isFixed(_ page: String) -> Bool {
        page.range(of: #"<meta[^>]*name=["']viewport["'][^>]*width\s*=\s*1920"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// `look_at_app`'s `shape`: "1920x1080", "390 x 844", "820×1180", each side 200 to 4000 CSS pixels.
    static func shape(_ text: String) -> CGSize? {
        let sides = text.lowercased().replacingOccurrences(of: "×", with: "x").split(separator: "x").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard sides.count == 2, let width = sides[0], let height = sides[1], (200...4000).contains(width), (200...4000).contains(height) else { return nil }
        return CGSize(width: width, height: height)
    }

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
        // On Android: Lamp's Android app around the page, as a game's.
        if project.openPlaces.contains(.android) { try GameAndroid.write(for: project) }
        try Template.put(Template.lampSupportSwift(for: project), at: project.dir.appendingPathComponent("Sources/LampSupport.swift"), for: project)
        try Template.write(GameKit.webBuildSh, to: "build.sh", for: project, executable: true)
        try Template.write(packageSwift, to: "Package.swift", for: project)
        try Template.write("A screen made with Lamp: a page in Web/, shown full screen.\n", to: marker, for: project)
    }

    /// The scaffold: a page that shows the app's name filling whatever it's shown on.
    static func fill(_ project: LampProject) throws {
        try Template.write(indexHTML, to: "Web/index.html", for: project)
        try Template.write(styleCSS, to: "Web/style.css", for: project)
        try Template.write(TVTemplate.appJS, to: "Web/app.js", for: project)
        try Template.write(appMd, to: "APP.md", for: project)
        try Template.write(".lamp/\n.build/\nbuild/\n", to: ".gitignore", for: project)
        try write(for: project)
    }

    static func remove(from project: LampProject) {
        for path in ["Sources/LampScreen.swift", GameAndroid.folder, marker] { AppFolder.remove(project.dir.appendingPathComponent(path), in: project.dir) }
        GameKit.removePage(from: project)
    }

    /// Every path Lamp owns in a screen.
    static func paths(for project: LampProject) -> [String] {
        [TVTemplate.supportFile, "Sources/LampScreen.swift", "Sources/LampPage.swift", "Sources/LampSupport.swift", "build.sh", "Package.swift", marker]
            + GameAndroid.paths(for: project)
    }

    static let indexHTML = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <title>{{NAME}}</title>
        <link rel="stylesheet" href="style.css">
        </head>
        <body>
        <main id="app">
          <h1>{{NAME}}</h1>
          <p class="status">Lamp is making this app.</p>
        </main>
        <script src="lamp.js"></script>
        <script src="app.js"></script>
        </body>
        </html>

        """

    /// Sized by the screen it's on (`--u`, a hundredth of its shorter side), so it reads the same from across a room on a
    /// TV, a frame or an iPad, and stays readable on a phone.
    static let styleCSS = """
        :root { --u: max(0.8vmin, 4px); }
        html, body {
          margin: 0;
          width: 100%;
          height: 100%;
          overflow: hidden;
          background: #101418;
          color: #f2f4f6;
          font-family: -apple-system, "Samsung One", "LG Smart UI", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          font-size: calc(var(--u) * 3.6);
        }
        #app {
          box-sizing: border-box;
          height: 100%;
          padding: calc(var(--u) * 5);
          display: flex;
          flex-direction: column;
          justify-content: center;
          align-items: center;
          text-align: center;
        }
        h1 { font-size: calc(var(--u) * 8); margin: 0 0 calc(var(--u) * 2); }
        .status { opacity: 0.7; }
        /* What has the remote's focus is always plain to see from the sofa. */
        :focus { outline: calc(var(--u) * 0.6) solid #4da3ff; outline-offset: calc(var(--u) * 0.6); }

        """

    static let appMd = """
    # {{NAME}}

    A screen built and changed with Lamp: a page in Web/ (HTML, CSS and JavaScript) shown full screen and glanced at from
    across a room, filling whatever it's shown on. It's a Mac app shown in its own window, and goes on an iPhone, an iPad, an Android tablet or photo
    frame, a Samsung or LG TV or an Xbox too once it's put there. Lamp looks at it in its TV preview on the Mac.

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
    static var stamp: String {
        (host ?? "") + (GameKit.page?.text ?? "") + GameKit.webBuildSh + packageSwift + TVTemplate.lampJS
            + GameAndroid.screenActivity + GameAndroid.screenManifest
    }
}

// MARK: - What the builder is told

extension Agent {
    /// The rules for a screen: the TV app's rules for the page (it's the same page), with where it's shown in the
    /// request's device line (`Rules.screenPlaces`), since a place may be given at any time.
    static func screenPrompt(for project: LampProject) -> String {
        let rules = [Rules.screenEdit, Rules.ask, Rules.shell, Rules.tvFrameworks, Rules.screenDesign, Rules.tvKeys, Rules.tvData, Rules.webAI, Rules.pageNative,
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
        let rules = [Rules.screenEdit, Rules.tvFrameworks, Rules.screenDesign, Rules.tvKeys, Rules.tvData, Rules.webAI, Rules.pageNative,
                     Rules.webSound, Rules.tvLogs, Rules.tvTry, alone ? "" : Rules.screenAmongApps + Rules.wishTalk]
        return (Rules.partHeader("a screen, a page in Web/ shown full screen and glanced at from across a room, at home on the Mac and shown on an iPhone or iPad, an Android tablet or photo frame, a TV and an Xbox too once it's put there", folder: folder)
                + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: "screen")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a screen")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "opens it again in the TV preview")
    }
}

extension Agent.Rules {
    static let screenHeader = """
    You are Lamp's builder agent. The current directory is a screen: a page (HTML, CSS and JavaScript in Web/) shown \
    full screen and glanced at from across a room, the same page wherever it's shown, filling the screen it's on. Its \
    home is the person's Mac, where it's an app in its own window; it's shown on an iPhone or iPad, an Android tablet or \
    photo frame, a Samsung or LG TV and the person's Xbox too once it's put there. You try it in the TV preview on this \
    Mac, the same page with a remote's keys, at any shape. The request's device line says where it's shown: never say \
    it's on a device it isn't on. Read APP.md first for context.
    """

    static let screenEdit = """
    - Make the change the user asks for by editing the page's files in Web/ (index.html, style.css, app.js and any \
    others), and what it shows beside them, and Sources/Native.swift for what the page asks of the device. Web/lamp.js, \
    the rest of Sources/, build.sh and Package.swift are Lamp's (the page's building blocks and the app around it): read lamp.js, never edit or delete any of them. Lamp builds by itself and, \
    at the end of your turn, opens the screen where Try On points (its window on this Mac, a simulator, the Android \
    emulator or tablet, a TV or the Xbox), so don't run a build, a server or a browser yourself, and leave .lamp/ alone. \
    Where else it's shown is the person's to ask for: when they \
    want it on their iPad, TV or Xbox, call make_app_for with the screen as {"kind": "screen", "places": [every place \
    beside the Mac it's to be on: "ipad", "android", "tv"…]} and every other app the wish keeps beside it in `apps`; it stays the \
    same screen.
    """

    /// How a screen looks: like a TV app's page (`tvDesign`), but filling whatever it's shown on rather than a fixed
    /// 1920x1080, and looked at in several shapes.
    static let screenDesign = """
    - Design for a screen glanced at from across a room that fills whatever it's on: a 16:9 TV, a Mac window of any \
    size, a photo frame, an iPad either way up, a phone. Lay it out as a responsive web page, never as a fixed canvas \
    scaled like a picture: CSS grid and flexbox that share out the space, type and spacing sized from the screen (a unit \
    such as `--u: max(0.8vmin, 4px)` with everything in multiples of it, or vmin and clamp()), and media queries that \
    change the layout with its shape ((orientation: portrait), (max-aspect-ratio: …), (max-width: …)): side by side \
    when it's wide, stacked when it's tall, fewer columns when it's narrow. On a TV and a landscape screen the page \
    never scrolls as a whole (lists scroll inside their own box), with a margin of about 5% a TV may cut off; on a tall \
    narrow screen a stacked column may scroll. Text easy to read from a few metres, headings much larger, high \
    contrast. Everything is reached with a remote's arrows and OK as well as by touch and the mouse: what has focus \
    must be unmistakable, focus moves the way the layout looks, targets are large, and nothing needs hover. Before you \
    finish, look at it in several shapes with `look_at_app`'s `shape`: "1920x1080" (a TV), "1280x800" (a photo frame), \
    "820x1180" (an iPad upright) and "390x844" (a phone). A page whose viewport is `width=1920` (a screen made before \
    screens filled any shape) is zoomed whole instead and looked at only as a TV: make it fill any shape when it's to \
    go on a phone, an iPad or a frame, starting with its viewport (`width=device-width, initial-scale=1`).
    """

    /// Where a screen is shown, for the request's device line.
    static func screenPlaces(_ project: LampProject) -> String {
        "It's shown on \(GameKit.spoken(project.openPlaces).replacingOccurrences(of: "your ", with: "the person's ")), and Try On points at the "
            + "\(GameKit.placeName(project.destination)) now. Keep it within what a TV's browser draws smoothly: plain HTML and CSS, few animations."
    }
}
