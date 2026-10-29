import Foundation

/// Screens, as Lamp once made them (`Platform.screen`): a web app, a page in `Web/` with the TV app's `Web/lamp.js`
/// (`TVTemplate`), shown wherever it's been put (`LampProject.places`). No new app is made one: what an app is (a game or
/// an app) and how it's made are the agent's to choose, and designing for a TV is the tv-design skill's, offered by
/// the TV rows of the table of devices (`Place.skills`) to any app on a TV. This keeps the screens already made loading,
/// building and restoring as they were: their folder and marker, their identity, and their page at its own address
/// (lamp-screen://app/), where its saved data is.
///
/// On the Mac, an iPhone and an iPad it's Lamp's common app around a page (`GameKit/apple/LampWebApp.swift`, with
/// LampPage.swift and LampSupport.swift), given the screen's address. The page fills whatever it's shown on, as a web page fills a
/// browser; one made at a fixed 1920x1080 (its viewport says so, `fillsAnyShape`) is zoomed to the window instead. On Android it's Lamp's Android app around the page, on a Samsung or LG TV the TV app's own way there (`TVs`),
/// and on the Xbox the integration's web app ("xbox-one"). Wherever it's shown, the agent looks at it in the TV preview
/// on the Mac (`Target.looksInTVPreview`), at any shape it asks for (`look_at_app`'s `shape`), so it never waits for a build of the Mac app to see a change.
///
/// A web app made now (`Platform.webApp`, `make_app_for`'s `kind` "app" with `made` "web") is written the same way,
/// with what's its own (`Page`): its marker, its own address and so its own saved data, and the folder it's installed
/// in. The two are never changed into each other: a screen stays a screen, its address and saves with it.
enum ScreenKit {
    /// What marks a screen's folder, kept with the code so a version restored brings the kind back with it.
    static let marker = ".lamp-screen"

    /// What's a kind's own in the app Lamp writes around its page.
    struct Page {
        let marker: String
        /// Where its page is served, which is where its saved data is kept: never changed for an app already made.
        let scheme: String
        /// The Swift around the page, by the file its builds and versions know.
        let swift: String
        let says: String
    }

    static let screenPage = Page(marker: marker, scheme: "lamp-screen", swift: "Sources/LampScreen.swift",
                                 says: "A screen made with Lamp: a page in Web/, shown full screen.\n")
    static let webAppPage = Page(marker: ".lamp-web-app", scheme: "lamp-web-app", swift: "Sources/LampWebApp.swift",
                                 says: "A web app made with Lamp: a page in Web/.\n")

    static func page(for platform: Platform) -> Page { platform == .webApp ? webAppPage : screenPage }

    /// Whether the kind is a web app around a page: a web app, or a screen made before.
    static func isWebApp(_ platform: Platform) -> Bool { platform == .screen || platform == .webApp }
    static func isScreen(_ project: LampProject) -> Bool { isWebApp(project.platform) }

    /// Shown on this Mac or an iPhone or iPad, where it's an app of Lamp's around the page.
    static func hostsOnApple(_ project: LampProject) -> Bool {
        isScreen(project) && (project.openPlaces.contains(.mac) || project.openPlaces.contains(.ios))
    }

    static func isMade(_ dir: URL) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path) }
    static func isWebAppMade(_ dir: URL) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(webAppPage.marker).path) }

    /// Whether the page fills any shape: its viewport isn't the fixed `width=1920` screens were laid out at before.
    static func fillsAnyShape(_ project: LampProject) -> Bool {
        guard let page = try? String(contentsOf: project.dir.appendingPathComponent("Web/index.html"), encoding: .utf8) else { return true }
        return !isFixed(page)
    }

    /// A page laid out at a fixed 1920x1080: its viewport meta names that width (Lamp's TV scaffold's
    /// `width=1920, height=1080`). The app around it is given that canvas only then (`host`).
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

    /// Where a screen's page is served, which is where its saved data is kept: never changed for a screen already made.
    static var scheme: String { screenPage.scheme }

    /// Lamp's common app around a page, as a kind has it: at its own address, its page laid out at the window's size, or at
    /// 1920x1080 and zoomed for a page made that way (`fillsAnyShape`). A screen's is still written as
    /// Sources/LampScreen.swift, the file a screen's build and every version of it know.
    private static func host(for project: LampProject) -> String? {
        GameKit.webApp(scheme: page(for: project.platform).scheme, canvas: fillsAnyShape(project) ? nil : (1920, 1080))
    }

    /// Lamp's own files, written before every turn and build: the page's script, the Swift around it, what builds it.
    static func write(for project: LampProject) throws {
        let page = page(for: project.platform)
        guard let host = host(for: project) else { throw Failure(message: "This copy of Lamp is missing its web app kit.") }
        try TVTemplate.writeOwnedFiles(for: project)
        try Template.write(host, to: page.swift, for: project)
        try GameKit.writePage(for: project)
        // On Android: Lamp's Android app around the page, as a game's.
        if project.openPlaces.contains(.android) { try GameAndroid.write(for: project) }
        try Template.put(Template.lampSupportSwift(for: project), at: project.dir.appendingPathComponent("Sources/LampSupport.swift"), for: project)
        // What the player's copy is told it is: the kind's address, and the fixed canvas a page made at one has.
        let played = GameKit.playerPlist(game: false, scheme: page.scheme, canvas: fillsAnyShape(project) ? nil : (1920, 1080))
        try Template.write(buildSh.replacingOccurrences(of: "{{PLAYER_PLIST}}", with: played), to: "build.sh", for: project, executable: true)
        try Template.write(packageSwift, to: "Package.swift", for: project)
        try Template.write(page.says, to: page.marker, for: project)
        // On Android: Lamp's Android app around the page, as a game's.
        if project.hasAndroid { try GameAndroid.write(for: project) }
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

    /// What Lamp wrote for the kind it was (`was`), gone once the app is another kind.
    static func remove(from project: LampProject, was: Platform) {
        let page = page(for: was)
        for path in [page.swift, GameAndroid.folder, page.marker] { AppFolder.remove(project.dir.appendingPathComponent(path), in: project.dir) }
        GameKit.removePage(from: project)
    }

    /// Every path Lamp owns in a screen or a web app.
    static func paths(for project: LampProject) -> [String] {
        let page = page(for: project.platform)
        return [TVTemplate.supportFile, page.swift, "Sources/LampPage.swift", "Sources/LampSupport.swift", "build.sh", "Package.swift", page.marker]
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

    A web app built and changed with Lamp: a page in Web/ (HTML, CSS and JavaScript) shown full screen, filling whatever
    it's shown on. It's a Mac app shown in its own window, and goes on an iPhone, an iPad, an Android device, a Samsung
    or LG TV or an Xbox too once it's put there. Lamp looks at it in its TV preview on the Mac.

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
    /// A page's build (`GameKit.webBuildSh`), turning every way on an iPhone or iPad: a screen fills an iPad upright as
    /// well as on its side, where a game keeps to landscape.
    static var buildSh: String {
        let landscape = "<string>UIInterfaceOrientationLandscapeRight</string><string>UIInterfaceOrientationLandscapeLeft</string>"
        let any = "<string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationPortraitUpsideDown</string>" + landscape
        return GameKit.webBuildSh.replacingOccurrences(of: landscape, with: any)
    }

    static var stamp: String {
        // Both ways the app around the page is written, at each kind's address: a change to either is a change of Lamp's.
        let hosts: String = [screenPage, webAppPage].map { page in
            (GameKit.webApp(scheme: page.scheme, canvas: nil) ?? "") + (GameKit.webApp(scheme: page.scheme, canvas: (1920, 1080)) ?? "")
        }.joined()
        let rest: String = (GameKit.page?.text ?? "") + buildSh + packageSwift
        return hosts + rest + TVTemplate.lampJS + GameAndroid.stamp
    }
}

// MARK: - What the builder is told

extension Agent {
    /// The rules for a screen: the TV app's rules for the page (it's the same page), with where it's shown in the
    /// request's device line (`Rules.screenPlaces`), since a place may be given at any time.
    static func screenPrompt(for project: LampProject) -> String {
        let rules = [Rules.screenEdit, Rules.ask, Rules.shell, Rules.tvFrameworks, Rules.screenDesign(project.openPlaces), Rules.tvKeys, Rules.tvData, Rules.webAI, Rules.pageNative,
                     Rules.webSound, Rules.icon, Rules.about, Rules.tvAttachments, Rules.tvLogs, Rules.tvTry, Rules.appMd, Rules.audience,
                     Skills.index(Skills.offered(.screen)), Rules.begin, Rules.finish]
        return (Rules.screenHeader + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: "screen")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a screen")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "opens it again in the TV preview")
    }

    /// The rules for a screen that's one of a wish's apps, in a folder of its own: the screen's own, for the files
    /// there, without those about the wish as a whole.
    static func screenPrompt(part folder: String, alone: Bool = false) -> String {
        let rules = [Rules.screenEdit, Rules.tvFrameworks, Rules.screenDesign(nil), Rules.tvKeys, Rules.tvData, Rules.webAI, Rules.pageNative,
                     Rules.webSound, Rules.tvLogs, Rules.tvTry, alone ? "" : Rules.screenAmongApps + Rules.wishTalk,
                     Skills.index(Skills.offered(.screen))]
        return (Rules.partHeader("a web app, a page in Web/ shown full screen, at home on the Mac and shown on any other device that takes a page (make_app_for's table of devices) once it's put there", folder: folder)
                + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: "screen")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a screen")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "opens it again in the TV preview")
    }
}

extension Agent.Rules {
    static let screenHeader = """
    You are Lamp's builder agent. The current directory is a web app: a page (HTML, CSS and JavaScript in Web/) shown \
    full screen, the same page wherever it's shown, filling the screen it's on. Its home is the person's Mac, \
    where it's an app in its own window; it's shown on any other device that takes a page (make_app_for's table of \
    devices) once it's put there. You try \
    it in the TV preview on this Mac, the same page with a remote's keys, at any shape. The request's device line says \
    where it's shown: never say it's on a device it isn't on. Read APP.md first for context.
    """

    static var screenEdit: String { """
    - Make the change the user asks for by editing the page's files in Web/ (index.html, style.css, app.js and any \
    others), and what it shows beside them, and Sources/Native.swift for what the page asks of the device. Web/lamp.js, \
    the rest of Sources/, build.sh and Package.swift are Lamp's (the page's building blocks and the app around it): read lamp.js, never edit or delete any of them. Lamp builds by itself and, \
    at the end of your turn, opens the screen where Try On points (its window on this Mac, a simulator, an Android \
    emulator or device, a TV or the Xbox), so don't run a build, a server or a browser yourself, and leave .lamp/ alone. \
    The page fills the screen it's on, whatever its shape (the design rule below). Where else it's shown is the \
    person's to ask for: when they want it somewhere else, call make_app_for with its folder in `app` ("." when it's the \
    wish's own folder), `kind` "app", `made` "web" and `devices` every device it's to be on ("mac", "ipad", "android", \
    "android-tv", "tv"…: a page goes wherever the table of devices gives a web host); it stays the same app, with its \
    saves, and the wish's other apps stay as they are.
    """ }

    /// How a screen looks: like a TV app's page (`tvDesign`), but filling whatever it's shown on rather than a fixed
    /// 1920x1080, and looked at in the shapes of the places it's shown (`places`, or nil to read them off the request's
    /// device line): a Mac web app is never sent to look at itself as a TV, a frame and a phone.
    static func screenDesign(_ places: [Destination]?) -> String { """
    - Design for a screen glanced at from across a room that fills whatever it's on: a 16:9 TV, a Mac window of any \
    size, a photo frame, an iPad either way up, a phone. Lay it out as a responsive web page, never as a fixed canvas \
    scaled like a picture: CSS grid and flexbox that share out the space, type and spacing sized from the screen (a unit \
    such as `--u: max(0.8vmin, 4px)` with everything in multiples of it, or vmin and clamp()), and media queries that \
    change the layout with its shape ((orientation: portrait), (max-aspect-ratio: …), (max-width: …)): side by side \
    when it's wide, stacked when it's tall, fewer columns when it's narrow. On a TV and a landscape screen the page \
    never scrolls as a whole (lists scroll inside their own box), with a margin of about 5% a TV may cut off; on a tall \
    narrow screen a stacked column may scroll. Text easy to read from a few meters, headings much larger, high \
    contrast. Everything is reached with a remote's arrows and OK as well as by touch and the mouse: what has focus \
    must be unmistakable, focus moves the way the layout looks, targets are large, and nothing needs hover. Before you \
    finish, look at it with `look_at_app`'s `shape` in the shapes of the places it's shown, and only those: \
    \(shapesToLook(places)). When it's put somewhere new, look at it in that place's shapes too. A page whose viewport \
    is `width=1920` (a screen made before screens filled any shape) is zoomed whole instead and looked at only as a TV: \
    make it fill any shape when it's to go on a phone, an iPad or a frame, starting with its viewport \
    (`width=device-width, initial-scale=1`).
    """ }

    /// The shapes a screen is looked at in for each place it's shown, as `look_at_app`'s `shape` takes them.
    static func screenShapes(_ place: Destination) -> [(shape: String, what: String)] {
        switch place {
        case .mac: [("1280x800", "a Mac window"), ("800x600", "a small Mac window")]
        case .ios: [("820x1180", "an iPad upright"), ("390x844", "an iPhone")]
        case .android: [("390x844", "an Android phone"), ("1280x800", "an Android tablet or photo frame")]
        case .androidTV, .tv, .device: [("1920x1080", "a TV")]
        }
    }

    /// The shapes to look at in before finishing: those of the places given, each once; with none given, each place's,
    /// for the places the request's device line names.
    static func shapesToLook(_ places: [Destination]?) -> String {
        guard let places, !places.isEmpty else {
            let all: [(String, [Destination])] = [("the Mac", [.mac]), ("an iPhone or iPad", [.ios]), ("an Android device", [.android]),
                                                  ("a TV or an Xbox", [.tv])]
            return "for each place the request's device line names, " + all.map { name, place in
                name + " " + place.flatMap(screenShapes).map { "\"\($0.shape)\"" }.joined(separator: " and ")
            }.joined(separator: "; ")
        }
        var shapes: [(shape: String, what: String)] = []
        for (shape, what) in places.flatMap(screenShapes) {
            if let at = shapes.firstIndex(where: { $0.shape == shape }) { shapes[at].what += " or " + what } else { shapes.append((shape, what)) }
        }
        return shapes.map { "\"\($0.shape)\" (\($0.what))" }.joined(separator: ", ")
    }

    /// Where a screen is shown, for the request's device line.
    static func screenPlaces(_ project: LampProject) -> String {
        "It's shown on \(GameKit.spoken(project.openPlaces).replacingOccurrences(of: "your ", with: "the person's ")), and Try On points at the "
            + "\(GameKit.placeName(project.destination)) now. Keep it within what a TV's browser draws smoothly: plain HTML and CSS, few animations."
    }
}
