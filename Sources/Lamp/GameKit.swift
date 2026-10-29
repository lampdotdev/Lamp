import AppKit
import CryptoKit
import Foundation

/// Games: Lamp's own kind of app (`Platform.game`), a page in `Web/` drawn with three.js, or with Phaser for a 2D game
/// (`web/lamp-phaser.js` over the runtime), and played through Lamp's game runtime (`web/lamp-game.js`) wherever the game has been put (`LampProject.places`). Its home is the Mac: a Mac app in
/// the person's Apps like any other, the page in a web view of the app's own inside a little Swift of Lamp's
/// (`LampWebGame.swift` and `LampPage.swift`, with LampSupport.swift, so it has the wand, the chat beside it and LampAI).
/// The same page goes on an iPhone or iPad through that app, on Android in Lamp's Android app (`GameAndroid`), and on the
/// Xbox as the integration's web app, installed as a game. The agent plays it in a preview on the Mac (`WebGamePreview`,
/// the page out of sight, from a script of the controller's moves), so its looks are the same frames every time.
///
/// A game made before three.js games is C++ against Lamp's game kit (`lamp_game.h`, sokol_gfx, the kit's own sound mix),
/// built on this Mac with LLVM and Microsoft's SDK (`WindowsTools`) for the Xbox alone, which is the only place it has,
/// and played in the kit's own Metal preview (`play`). New games aren't made in C++.
enum GameKit {
    static let kind = "native-game"
    /// The size every game is drawn at, everywhere, scaled to the screen.
    static let width = 1920, height = 1080
    static let folder = "Lamp"
    /// What marks a game's folder, kept with the code so a version restored brings the kind back with it.
    static let marker = ".lamp-game"
    /// The Xbox's integration, and the kind of its apps a game is when it's on one (`LampProject.integration`).
    static let xbox = "xbox-one"
    static let xboxKind = "xbox-one:game"
    /// The integrations a page made for several devices (a game, a screen) goes onto as their web app
    /// (`integration(for:)`): the only one Lamp packages such a page for so far is the Xbox's.
    static let pageIntegrations: Set<String> = [xbox]

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Whether the app is a game.
    static func isGame(_ project: LampProject) -> Bool { project.platform == .game }

    /// What a game is written for: a page on Lamp's game runtime (`web`, the start for most games: the model writes it
    /// best, and it runs in every place's web view), or C++ on the kit (`native`, for a heavy 3D game that needs an
    /// Xbox's whole power). Its folder's mark says which, so a version restored brings the engine with it; a draft's is
    /// its meta.json's; a game made before engines (the mark says nothing of one) is native, as every game was then.
    enum Engine: String { case web, native }

    static func engine(_ project: LampProject) -> Engine {
        if let mark = AppFile.text(project.dir.appendingPathComponent(marker), in: project) {
            return mark.contains("engine: web") ? .web : .native
        }
        return project.engine.flatMap(Engine.init(rawValue:)) ?? (DeviceApps.isScaffolded(project.dir) ? .native : .web)
    }

    /// The engine a new game is made with: a page on the runtime. C++ on the kit is only what games made before three.js games are.
    static func engine(for devices: Set<String>) -> Engine { .web }

    /// The Xbox integration's kind a game goes there as: its web app's for a web game, its game kind's for C++.
    static func xboxKind(for engine: Engine) -> String { engine == .web ? xbox : xboxKind }

    // MARK: Where it's played

    /// A list of devices that makes a game: "game" with any of its places, or the Xbox's game kind a naming call from
    /// before games were a kind of their own gave.
    static func claims(_ devices: Set<String>) -> Bool {
        // A new game is a web game: the C++ kind's own word ("xbox-one:game") makes nothing new. Where it's played is
        // given apart, as its places: "mac" beside "game" is a Mac app.
        devices == ["game"]
    }

    /// The integration a game reaches its Xbox through, when the Xbox is one of its places: worked out from its places,
    /// which meta.json keeps, so setting the places, choosing the kind and a restore all agree.
    static func integration(for project: LampProject) -> String? {
        guard project.openPlaces.contains(.device) else { return nil }
        // A screen goes on the Xbox as its web app; a game as the kind its engine makes.
        return ScreenKit.isScreen(project) ? xbox : xboxKind(for: engine(project))
    }

    /// What a place is called to the person and to the agent.
    static func placeName(_ place: Destination) -> String {
        switch place {
        case .ios: "iPhone and iPad"
        case .android: "Android"
        case .androidTV: "Android TV"
        case .tv: "Samsung or LG TV"
        case .device: "Xbox"
        default: "Mac"
        }
    }

    /// The model of the Xbox a game goes to, as Device Portal names it ("Xbox Series X"): the one chosen under Try On,
    /// else the slowest of the person's. Nil when that isn't known: no Xbox set up yet, or one whose setup hasn't reached
    /// Device Portal (its description says Xbox One on every console).
    static func xboxModel(for project: LampProject) -> String? {
        let xboxes = Integrations.kept().filter { $0.integration == xbox }
        if let chosen = xboxes.first(where: { $0.id == project.device }) { return Integrations.readModel(of: chosen) }
        let models = xboxes.map(Integrations.readModel(of:))
        guard !models.isEmpty, !models.contains(nil) else { return nil }
        let known = models.compactMap { $0 }
        return known.first { !$0.localizedCaseInsensitiveContains("Series") }
            ?? known.first { !$0.localizedCaseInsensitiveContains("Series X") } ?? known.first
    }

    /// The places as the person hears them: "your Mac, your iPhone or iPad and your Xbox".
    static func spoken(_ places: [Destination]) -> String {
        let names = places.map {
            $0 == .ios ? "your iPhone or iPad" : $0 == .android ? "your Android phone or tablet" : $0 == .androidTV ? "your Google TV, Android TV or Fire TV"
                : $0 == .tv ? "your Samsung or LG TV" : "your " + placeName($0)
        }
        return names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    /// Whether a folder holds a game: its marker, or the device marker a game made before games were a kind of their
    /// own left, naming the Xbox's game kind.
    static func isMade(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path)
            || DeviceApps.integrationID(in: dir).map { DeviceApps.appKind($0)?.lamp == kind } == true
            || isXboxWebGame(dir)
    }

    /// Whether a folder holds a game made as the Xbox's web app before games were a kind of their own: the web app's
    /// marker, a page in Web/, and the agent's own line that it's a game (capabilities.json's `game`, or icon.json's,
    /// which it wrote for every game before capabilities.json asked). Not three.js alone: it draws scenes that aren't
    /// games, and a game may draw without it. An Xbox app of menus and pages has none of these and stays the Xbox's.
    static func isXboxWebGame(_ dir: URL) -> Bool {
        guard DeviceApps.integrationID(in: dir) == xbox,
              FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(webFolder)/index.html").path) else { return false }
        if Template.Capabilities.load(dir.appendingPathComponent(Template.Capabilities.file)).game == true { return true }
        struct Icon: Decodable { let game: Bool? }
        let icon = AppFile.read(dir.appendingPathComponent("icon.json"), inFolder: dir).flatMap { try? JSONDecoder().decode(Icon.self, from: $0) }
        return icon?.game == true
    }

    /// Whether a game made as the Xbox's web app (`isXboxWebGame`) still runs its own loop and input rather than Lamp's
    /// game runtime: none of its page's own files load lamp-game.js. The preview's scripted plays need `game()`, so such a
    /// page is looked at and used in the page preview it had as the Xbox's web app, until it's moved onto the runtime.
    static func ownsLoop(_ project: LampProject) -> Bool {
        guard isGame(project), engine(project) == .web, isXboxWebGame(project.dir) else { return false }
        let page = project.dir.appendingPathComponent(webFolder)
        guard let walk = FileManager.default.enumerator(at: page, includingPropertiesForKeys: [.isRegularFileKey]) else { return true }
        let lamps: Set<String> = ["lamp-game.js", "lamp.js", "lamp-controllers.js", "lamp-device.js"]
        for case let url as URL in walk {
            if url.hasDirectoryPath, url.lastPathComponent.hasPrefix("three") { walk.skipDescendants(); continue }
            guard ["js", "mjs", "html"].contains(url.pathExtension.lowercased()), !lamps.contains(url.lastPathComponent),
                  let text = AppFile.text(url, in: project) else { continue }
            if text.contains("lamp-game.js") { return false }
        }
        return true
    }

    /// A meta.json from before games were a kind of their own, of a game made as the Xbox's web app (`isXboxWebGame`):
    /// a web game now, at home on the Mac, with the Xbox one of its places and its console still the one chosen
    /// there, so it goes on as a game and is updated. Only meta.json changes: the code, its versions, chat and icon are
    /// as they were, and the folder reads as a game in every version of it (`isMade`), so a restore keeps it one.
    static func migratedWebGame(_ project: LampProject) -> LampProject? {
        // A wish with other apps in folders is left as it is: its Xbox app is one of several, the person's to change.
        guard project.platform == .device, project.integration == xbox, project.partFolders.isEmpty, isXboxWebGame(project.dir) else { return nil }
        var game = project
        game.platform = .game
        game.engine = Engine.web.rawValue
        game.places = [.mac, .device]
        game.chosen = .mac
        game.integration = integration(for: game)
        game.apps = game.apps.map { $0.kind == .device && ($0.integration == nil || $0.integration == xbox) ? WishApp(kind: .game) : $0 }
        return game
    }

    /// A meta.json from before games were a kind of their own: a device app of the Xbox's game kind. It's a game now,
    /// at home on the Mac, with the Xbox one of its places and still where Try On points.
    static func migrated(_ project: LampProject) -> LampProject? {
        guard project.platform == .device, let integration = project.integration, DeviceApps.appKind(integration)?.lamp == kind else { return nil }
        var game = project
        game.platform = .game
        // On the Xbox alone, as it was: Lamp makes no app around a C++ game for other places.
        game.places = [.device]
        game.chosen = .device
        // Its list of apps named the device app it was: that one app is the game now, not another still to be made.
        game.apps = game.apps.map { $0.kind == .device && ($0.integration == nil || $0.integration == integration) ? WishApp(kind: .game) : $0 }
        return game
    }

    // MARK: Lamp's files in the game

    private static var resources: URL? { Bundle.main.resourceURL?.appendingPathComponent("GameKit") }

    /// Lamp's files, by name in `Lamp/`: the kit's own and the libraries it carries, flat.
    static let files: [(name: String, data: Data)] = {
        guard let resources else { return [] }
        let fm = FileManager.default
        var found: [(String, Data)] = []
        for folder in [resources, resources.appendingPathComponent("libraries")] {
            for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where !name.hasPrefix(".") {
                var isFolder: ObjCBool = false
                let url = folder.appendingPathComponent(name)
                guard fm.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue, let data = try? Data(contentsOf: url) else { continue }
                found.append((name, data))
            }
        }
        return found.sorted { $0.0 < $1.0 }
    }()

    /// A web game's: the Swift around its page, Lamp's runtime the page plays through, and the runtime's Phaser half, for
    /// a 2D game (written in every game, so the agent can read it before the game uses it; Phaser itself only then).
    static let webFiles: [(path: String, text: String)] = read([("Sources/LampGame.swift", "apple/LampWebGame.swift"),
                                                                 ("\(webFolder)/lamp-game.js", "web/lamp-game.js"),
                                                                 (phaserRuntime, "web/lamp-phaser.js")])
    /// Where Lamp puts the runtime's Phaser half, and Phaser beside it.
    static let phaserRuntime = "\(webFolder)/lamp-phaser.js"
    static let phaserFolder = "\(webFolder)/phaser"

    /// Lamp's common host for a page on Apple's devices (a web game's and a screen's: serving and showing it, LampAI
    /// through the app, and `LampNative` calls of the device); and where those calls are answered, the app's own Swift, written only
    /// when the app has none yet.
    static let page: (path: String, text: String)? = read([("Sources/LampPage.swift", "apple/LampPage.swift")]).first
    static let native: (path: String, text: String)? = read([("Sources/Native.swift", "apple/Native.swift")]).first

    /// Lamp's common app around a page (apple/LampWebApp.swift), for a page served at `scheme`://app/, which is where
    /// what it saves is kept, laid out at `canvas` and zoomed to the window, or at the window's own size without one.
    static func webApp(scheme: String, canvas: (width: Int, height: Int)?) -> String? {
        read([("", "apple/LampWebApp.swift")]).first.map { file in
            file.text.replacingOccurrences(of: "{{PAGE_SCHEME}}", with: scheme)
                .replacingOccurrences(of: "{{PAGE_CANVAS}}", with: canvas.map { "CGSize(width: \($0.width), height: \($0.height))" } ?? "nil")
        }
    }

    // MARK: Lamp's player

    /// Lamp's player (`apple/LampPlayer.swift`): the Mac app around a page, compiled once when Lamp is built (build.sh,
    /// from `playerSources`) and copied for every game and screen played on this Mac, so one opens in about a second and
    /// with none of Apple's tools. Nothing of a game is in it: each copy reads what it is from its own bundle, which
    /// build.sh writes as it copies it (its Info.plist, `playerPlist`, and the page in Resources/Web), as `stageSigned`
    /// does for every Mac app (install values, permission reasons, icon, signature). Not an .app inside Lamp's bundle,
    /// so the system never lists it as an app of its own.
    static let playerFolder = "LampPlayer.bundle"
    static let playerExe = "LampPlayer"
    static let playerSourcesFlag = "--player-sources"
    /// Where a game's page is served (`LampGamePage` in LampWebGame.swift), and so where what it saves is kept.
    static let gameScheme = "lamp-game"

    static var playerURL: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(playerFolder),
              FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/\(playerExe)").path) else { return nil }
        return url
    }

    /// What the player in Lamp's bundle was compiled from, by its contents (`playerSourcesVersion`, written into its
    /// Info.plist as it's built): stamped on every copy (`BuildStamp.player`), so a game an older player made is made again.
    static let playerVersion: String? = playerURL.flatMap {
        NSDictionary(contentsOf: $0.appendingPathComponent("Contents/Info.plist"))?["LampPlayerVersion"] as? String
    }

    /// The player's Swift, by its path in the package build.sh compiles: what a game or a screen is compiled from, with
    /// what Lamp fills in for each one read from the copy's Info.plist instead (`LampPlayer`), and both apps' `@main`
    /// left to main.swift, which picks one as the copy opens.
    static var playerSources: [(path: String, text: String)]? {
        let host = read([("", "apple/LampWebApp.swift"), ("", "apple/LampPlayer.swift")])
        guard let game = webFiles.first(where: { $0.path == "Sources/LampGame.swift" }), let page, let native, host.count == 2 else { return nil }
        func filled(_ text: String) -> String {
            text.replacingOccurrences(of: "@main\n", with: "")
                .replacingOccurrences(of: "\"{{NAME}}\"", with: "LampPlayer.name")
                .replacingOccurrences(of: "\"{{PAGE_SCHEME}}\"", with: "LampPlayer.scheme")
                .replacingOccurrences(of: "{{PAGE_CANVAS}}", with: "LampPlayer.canvas")
        }
        return [("Sources/main.swift", host[1].text), ("Sources/LampGame.swift", filled(game.text)), ("Sources/LampWebApp.swift", filled(host[0].text)),
                ("Sources/LampPage.swift", page.text), ("Sources/Native.swift", native.text), ("Sources/LampSupport.swift", Template.lampSupportSwift),
                ("Package.swift", webPackageSwift.replacingOccurrences(of: "{{EXE}}", with: playerExe))]
    }

    static func playerSourcesVersion(_ sources: [(path: String, text: String)]) -> String {
        var hasher = SHA256()
        for file in sources { hasher.update(data: Data((file.path + "\n" + file.text).utf8)) }
        return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// `Lamp --player-sources <folder>`: writes the player's package there, and its version beside it, for build.sh to
    /// compile into Lamp's bundle.
    static func writePlayerSourcesFromCommandLine() -> Never {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: playerSourcesFlag), index + 1 < arguments.count, let sources = playerSources else {
            FileHandle.standardError.write(Data("Lamp's game kit is missing, or no folder was given.\n".utf8))
            exit(1)
        }
        let folder = URL(fileURLWithPath: arguments[index + 1])
        // A placeholder Lamp fills for a compiled app that the player doesn't read for itself would compile as a word in
        // a string and show in every game: the build stops instead.
        for file in sources where ["Sources/LampGame.swift", "Sources/LampWebApp.swift"].contains(file.path) {
            for line in file.text.split(separator: "\n") where line.contains("{{") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                FileHandle.standardError.write(Data("The player doesn't fill in \(file.path)'s line: \(line)\n".utf8))
                exit(1)
            }
        }
        do {
            for file in sources {
                let url = folder.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file.text.write(to: url, atomically: true, encoding: .utf8)
            }
            try playerSourcesVersion(sources).write(to: folder.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("Couldn't write the player's Swift: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        exit(0)
    }

    /// Whether the app is a page in an app of Lamp's own on the Mac (a three.js game, a screen, a web app).
    static func hostsPage(_ project: LampProject) -> Bool {
        (isGame(project) && engine(project) == .web) || ScreenKit.isScreen(project)
    }

    /// Lamp's own Swift in a page's app: the player has all of it. `Native.swift` too while it's still Lamp's.
    private static let ownSwift: Set<String> = Set(["Sources/LampSupport.swift", "Sources/LampPage.swift", "Sources/LampGame.swift",
                                                     ScreenKit.screenPage.swift, ScreenKit.webAppPage.swift].map { String($0.dropFirst("Sources/".count)) })

    /// Swift of the app's own beside Lamp's, in Sources/ (what its Package.swift compiles): a `Native.swift` that answers
    /// the page's calls of the device (Home HQ's calendars and photos), or any other file. Such an app is compiled.
    static func hasOwnSwift(_ project: LampProject) -> Bool {
        let sources = project.dir.appendingPathComponent("Sources")
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: sources.path)) ?? [] where path.hasSuffix(".swift") {
            if ownSwift.contains(path) { continue }
            if path == "Native.swift", let native,
               AppFile.text(sources.appendingPathComponent(path), in: project) == native.text { continue }
            return true
        }
        return false
    }

    /// Whether the app's Mac copy is Lamp's player, copied rather than compiled: a page with no Swift of its own, on a
    /// Lamp that carries the player. Decided at every build, so one that comes to have Swift of its own is compiled
    /// from then on, and one whose Swift is taken away is copied again.
    static func usesPlayer(_ project: LampProject) -> Bool {
        hostsPage(project) && playerVersion != nil && !hasOwnSwift(project)
    }

    /// What build.sh is given to copy the player for the Mac rather than compile (`LAMP_PLAYER`), with its version for the
    /// copy's stamp; nothing for an app that's compiled, or for any other place.
    static func playerEnvironment(for project: LampProject) -> [String: String] {
        guard project.destination == .mac, usesPlayer(project), let url = playerURL, let version = playerVersion else { return [:] }
        return ["LAMP_PLAYER": url.path, "LAMP_PLAYER_VERSION": version]
    }

    /// What a Mac build of the page is made from beside its files (`Target.Recipe.inputs`): the player it's copied from,
    /// so a new one makes it again, or that it's compiled.
    static func playerInput(for project: LampProject) -> String {
        guard project.destination == .mac else { return "" }
        return usesPlayer(project) ? "player " + (playerVersion ?? "") : "compiled"
    }

    /// The lines of the copy's Info.plist that say what it is (`LampPlayer` in LampPlayer.swift): a game's window or any
    /// other page's, where the page is served, and the fixed size one is laid out at. A compiled app has these in its
    /// code and ignores them.
    static func playerPlist(game: Bool, scheme: String, canvas: (width: Int, height: Int)?) -> String {
        "  <key>LampPlayer</key><dict><key>kind</key><string>\(game ? "game" : "page")</string><key>scheme</key><string>\(scheme)</string>"
            + (canvas.map { "<key>canvas</key><string>\($0.width)x\($0.height)</string>" } ?? "") + "</dict>"
    }

    /// Writes the page's bridge, and the app's `Native` when it has none.
    static func writePage(for project: LampProject) throws {
        guard let page, let native else { throw Failure(message: "This copy of Lamp is missing its game kit.") }
        try Template.write(pageText(page.text, for: project), to: page.path, for: project)
        if !FileManager.default.fileExists(atPath: project.dir.appendingPathComponent(native.path).path) {
            try Template.write(native.text, to: native.path, for: project)
        }
    }

    /// lamp.js as a game is given it: Lamp's web building blocks, `Lamp.controllers` (phones on the Wi-Fi as players,
    /// joining from the game's Phone/ page), and `Lamp.wish`, the TV app's block for the wish's other apps and its own
    /// other copies, for a game that carries it (`Template.carriesWish`).
    static func lampJS(for project: LampProject) -> String {
        DeviceSupport.webJS + controllersJS + (Template.carriesWish(project) ? TVTemplate.wishJS : "")
    }

    /// A game's page has no `Lamp` of its own (a TV app's remote makes it), so the blocks make one to hang from.
    static let controllersJS = "\nwindow.Lamp = window.Lamp || {};\n" + TVTemplate.controllersJS

    /// The page's bridge as an app is given it: with the page's way to `LampWish` for an app that carries it
    /// (`Template.carriesWish`), since only such an app's LampSupport.swift has `LampWish`.
    static func pageText(_ text: String, for project: LampProject) -> String {
        Template.carriesWish(project) ? text : withoutWish(page: text)
    }

    static func withoutWish(page text: String) -> String {
        var text = text.replacingOccurrences(of: pageWishLine, with: "")
        if let start = text.range(of: "// MARK: - The wish's other apps\n"),
           let end = text.range(of: "// MARK: - The page's log\n", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.lowerBound)
        }
        return text
    }

    private static let pageWishLine = """
            configuration.userContentController.add(LampPageWish(scheme: scheme), contentWorld: .page, name: "lampWish") // the wish's other apps

    """

    /// Takes the page's bridge away, with the app's `Native` while it's still the one Lamp wrote: an app that's no
    /// longer a page has no use for either, and its code no longer has what they name.
    static func removePage(from project: LampProject) {
        guard let page, let native else { return }
        AppFolder.remove(project.dir.appendingPathComponent(page.path), in: project.dir)
        let own = project.dir.appendingPathComponent(native.path)
        if (try? String(contentsOf: own, encoding: .utf8)) == native.text { AppFolder.remove(own, in: project.dir) }
    }

    /// Where a web game's page is: the folder an Xbox web app keeps its page in, so the game goes on the Xbox as one.
    static let webFolder = "Web"

    /// A game written in TypeScript keeps its source in src/, with src/main.ts its entry, as a Vite project does, so a
    /// game brought in from one stays as its authors wrote it. Lamp bundles it into Web/app/ (`compileSource`) before
    /// every build and every look: every place plays plain JavaScript beside the rest of Web/, and index.html loads
    /// app/main.js (and app/main.css when the source imports CSS). Bare imports ("three", "lamp-game") stay as they are,
    /// for the page's import map.
    static let sourceFolder = "src"
    static let compiledFolder = "\(webFolder)/app"

    static func compilesSource(_ project: LampProject) -> Bool {
        FileManager.default.fileExists(atPath: project.dir.appendingPathComponent("\(sourceFolder)/main.ts").path)
    }

    /// Bundles a TypeScript game's src/ into Web/app/ with the Bun inside Lamp's own pi (run as Bun itself), in the
    /// game's sandbox: nothing to install and nothing fetched. It strips the types and doesn't check them. What fails
    /// is the build's failure, in Bun's words.
    static func compileSource(_ project: LampProject) async throws {
        guard engine(project) == .web, compilesSource(project) else { return }
        guard let bun = Agent.executable else { throw Failure(message: "This copy of Lamp is missing what compiles the game's TypeScript.") }
        // Bun looks for its settings in every folder above the one it builds in, which the game's sandbox doesn't let
        // it read in the person's own folders: it builds a copy of src/ in a scratch folder the sandbox opens, and the
        // page it made is put in Web/app/ from there.
        let scratch = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("lamp-ts-\(project.id)-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let command = "/bin/mkdir -p \"$LAMP_SCRATCH\" && /bin/cp -Rp \(Sandbox.quoted(sourceFolder)) \"$LAMP_SCRATCH/src\" "
            + "&& cd \"$LAMP_SCRATCH\" && BUN_BE_BUN=1 \(Sandbox.quoted(bun.path)) build src/main.ts --outdir app --target browser --format esm "
            + "--splitting --packages external --chunk-naming 'chunk-[hash].[ext]' --asset-naming '[name]-[hash].[ext]' "
            + "&& cd \"$LAMP_APP\" && /bin/rm -rf \(Sandbox.quoted(compiledFolder)) && /bin/cp -Rp \"$LAMP_SCRATCH/app\" \(Sandbox.quoted(compiledFolder))"
        var output: [String] = []
        let status = await Sandbox.run(command, for: project, cwd: project.dir,
                                       env: ["LAMP_SCRATCH": scratch.path, "LAMP_APP": project.dir.path],
                                       opening: [scratch.path], reading: [bun.deletingLastPathComponent().path]) { output.append($0) }
        guard status == 0 else {
            throw Failure(message: (["The game's TypeScript doesn't build:"] + output.suffix(30)).joined(separator: "\n"))
        }
    }
    /// Where Rapier goes in a game whose page imports it, by the name its import map gives it.
    static let rapierFolder = "\(webFolder)/rapier"
    static let rapierImport = "@dimforge/rapier3d-compat"

    /// Whether the game's page imports Rapier (its import map names it), so Lamp puts it beside the page.
    static func usesRapier(_ project: LampProject) -> Bool {
        DeviceSupport.pageNames([rapierImport], project, page: webFolder)
    }

    /// The controllers a game names buttons for (`Controllers`), which lamp-game.js imports.
    static let controllersFile = "\(webFolder)/lamp-controllers.js"

    private static func read(_ list: [(path: String, from: String)]) -> [(path: String, text: String)] {
        guard let resources else { return [] }
        return list.compactMap { path, from in (try? String(contentsOf: resources.appendingPathComponent(from), encoding: .utf8)).map { (path, $0) } }
    }

    /// Names every file of the kit's by its contents, so the build compiles Lamp's code again only when it changed, and
    /// a game is built again when Lamp's part of it changed (`Target.Recipe.inputs`).
    static let stamp: String = {
        var hasher = SHA256()
        for file in files { hasher.update(data: Data(file.name.utf8)); hasher.update(data: file.data) }
        // And the app around it on Apple's devices, which a new Lamp may change while the kit stays as it was.
        for file in webFiles + [page, native].compactMap({ $0 }) { hasher.update(data: Data((file.path + file.text).utf8)) }
        hasher.update(data: Data((webBuildSh + webPackageSwift + Controllers.pageJS).utf8))
        // And Lamp's Android app around it, with the Kotlin blocks a game of several apps carries there, so a game on
        // Android built by an earlier Lamp is built again rather than shown to its wish's other apps as out of date.
        hasher.update(data: Data((GameAndroid.mainActivity + GameAndroid.pageGateway + GameAndroid.screenManifest + GameAndroid.pageWish + GameAndroid.wishBuildGradle + Template.androidSupportKotlin).utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined() + "\n"
    }()

    /// Every path Lamp owns in a game, as written in its folder.
    static func paths(for project: LampProject) -> [String] {
        let common = ["Sources/LampSupport.swift", "build.sh", "Package.swift", marker]
        // A C++ game made before three.js games is the kit's alone, played on the Xbox and in the preview.
        guard engine(project) == .web else { return files.map { "\(folder)/\($0.name)" } + ["\(folder)/kit.stamp", marker] }
        return webFiles.map(\.path) + [page?.path ?? "Sources/LampPage.swift", "\(webFolder)/lamp.js", controllersFile] + DeviceSupport.threeFiles.map { "\(webFolder)/three/\($0.name)" }
            + DeviceSupport.rapierFiles.map { "\(rapierFolder)/\($0.name)" }
            + DeviceSupport.phaserFiles.map { "\(phaserFolder)/\($0.name)" } + common
            + GameAndroid.paths(for: project)
    }

    /// Writes Lamp's files into the game where they differ from what's there (so their dates move only when the kit
    /// changed), and the stamp after them; then the Swift around it and what builds it on Apple's devices.
    static func write(for project: LampProject) throws {
        let engine = engine(project)
        if engine == .web {
            try Template.put(Template.lampSupportSwift(for: project), at: project.dir.appendingPathComponent("Sources/LampSupport.swift"), for: project)
            guard webFiles.count == 3, !DeviceSupport.threeFiles.isEmpty, !DeviceSupport.phaserFiles.isEmpty else { throw Failure(message: "This copy of Lamp is missing its game kit.") }
            for file in webFiles { try Template.write(file.text, to: file.path, for: project) }
            // The controllers lamp-game.js names buttons for. The device the page is on isn't written here: each copy of
            // the page gets its own (`GamePage`).
            try Template.put(Controllers.pageJS, at: project.dir.appendingPathComponent(controllersFile), for: project)
            try writePage(for: project)
            for file in DeviceSupport.threeFiles(for: project, page: webFolder) {
                try Template.put(file.contents, at: project.dir.appendingPathComponent("\(webFolder)/three/\(file.name)"), for: project)
            }
            // Rapier only once the page imports it: it's bigger than three.js, and most games need no physics.
            if usesRapier(project) {
                for file in DeviceSupport.rapierFiles {
                    try Template.put(file.contents, at: project.dir.appendingPathComponent("\(rapierFolder)/\(file.name)"), for: project)
                }
            } else {
                AppFolder.remove(project.dir.appendingPathComponent(rapierFolder), in: project.dir)
            }
            // Phaser while the page draws with it, and taken away once it doesn't.
            if DeviceSupport.usesPhaser(project, page: webFolder) {
                for file in DeviceSupport.phaserFiles {
                    try Template.put(file.contents, at: project.dir.appendingPathComponent("\(phaserFolder)/\(file.name)"), for: project)
                }
            } else {
                AppFolder.remove(project.dir.appendingPathComponent(phaserFolder), in: project.dir)
            }
            // On the Xbox, Lamp's building blocks for its web apps (the controller's keys and rumble in its host);
            // elsewhere the same blocks, LampAI and LampStore reaching Lamp through the app around the page. Either way
            // lamp.js is the game's own on top: the game's code is the same everywhere, so it finds `Lamp.controllers`
            // (over the host's pipe on the Xbox, and saying it can't start where phones aren't hosted) and `Lamp.wish` on the Xbox too, where the page is
            // the wish's peer itself and the host opens its links.
            if project.integration != nil { try DeviceSupport.writeDeclared(for: project) }
            try Template.put(lampJS(for: project), at: project.dir.appendingPathComponent("\(webFolder)/lamp.js"), for: project)
            // On Android too: Lamp's Android app around the page.
            if project.hasAndroid { try GameAndroid.write(for: project) }
            let played = playerPlist(game: true, scheme: gameScheme, canvas: nil)
            try Template.write(webBuildSh.replacingOccurrences(of: "{{PLAYER_PLIST}}", with: played), to: "build.sh", for: project, executable: true)
            try Template.write(webPackageSwift, to: "Package.swift", for: project)
            try Template.write("A game made with Lamp: a page drawn with three.js or Phaser in Web/.\nengine: web\n", to: marker, for: project)
            return
        }
        // A C++ game: the kit, as Lamp had it before three.js games, for the Xbox and the preview.
        guard !files.isEmpty else { throw Failure(message: "This copy of Lamp is missing its game kit.") }
        for file in files {
            try Template.put(file.data, at: project.dir.appendingPathComponent("\(folder)/\(file.name)"), for: project)
        }
        try Template.put(stamp, at: project.dir.appendingPathComponent("\(folder)/kit.stamp"), for: project)
        try Template.write("A game made with Lamp: C++ in Game/ against Lamp's game kit in Lamp/.\nengine: native\n", to: marker, for: project)
        // A game made before games were a kind of their own was marked as a device app's.
        if DeviceApps.isScaffolded(project.dir) { AppFolder.remove(project.dir.appendingPathComponent(DeviceApps.marker), in: project.dir) }
    }

    /// Takes Lamp's game files out of an app that's no longer a game, so its next kind builds without them; the
    /// game's own code in Game/ is the agent's to move and delete.
    static func remove(from project: LampProject) {
        for path in [folder, "Sources/LampGame.swift", "\(webFolder)/lamp-game.js", phaserRuntime, controllersFile, "\(webFolder)/three", rapierFolder, phaserFolder, marker] {
            AppFolder.remove(project.dir.appendingPathComponent(path), in: project.dir)
        }
        removePage(from: project)
    }

    /// The scaffold: a game that already draws and moves, for the agent to make into the one asked for.
    static func fill(_ project: LampProject) throws {
        guard let resources else { throw Failure(message: "This copy of Lamp is missing its game kit.") }
        let web = engine(project) == .web
        let scaffold = resources.appendingPathComponent(web ? "scaffold-web" : "scaffold")
        for path in web ? ["\(webFolder)/index.html", "\(webFolder)/game.js"] : ["Game/game.cpp", "Game/scene.glsl"] {
            let text = try String(contentsOf: scaffold.appendingPathComponent(path), encoding: .utf8)
            try Template.write(text, to: path, for: project)
        }
        if !web {
            try Template.write("Models, pictures and sounds the game reads with lamp_asset(\"name\") go in this folder.\n", to: "Assets/README.txt", for: project)
        }
        try Template.write(".lamp/\n.build/\nbuild/\n", to: ".gitignore", for: project)
        try Template.write(web ? webAppMd : appMd, to: "APP.md", for: project)
        try write(for: project)
    }

    /// Whether the game is still the scaffold: its code is as Lamp wrote it.
    static func isScaffold(_ project: LampProject) -> Bool {
        let path = engine(project) == .web ? "\(webFolder)/game.js" : "Game/game.cpp"
        guard let scaffold = resources?.appendingPathComponent((engine(project) == .web ? "scaffold-web/" : "scaffold/") + path),
              let written = try? String(contentsOf: scaffold, encoding: .utf8),
              let now = AppFile.text(project.dir.appendingPathComponent(path), in: project) else { return false }
        return now == written.replacingOccurrences(of: "{{NAME}}", with: project.name)
    }

    static let webAppMd = """
    # {{NAME}}

    A game built and changed with Lamp: a page in Web/ drawn with three.js (or Phaser, for 2D) and played through Lamp's
    game runtime (Web/lamp-game.js), its models, pictures and sounds beside it. It's a Mac app played in its own window, and goes on
    an iPhone, an iPad or an Xbox too once it's put there. Lamp plays it in a preview on the Mac to try it.

    ## What it does
    Nothing yet: fresh scaffold, a card saying "Lamp is making this game.", for the game to replace.

    """

    static let appMd = """
    # {{NAME}}

    A game built and changed with Lamp: C++ in Game/ against Lamp's game kit (Lamp/lamp_game.h), with its models,
    pictures and sounds in Assets/. It's a Mac app played in its own window, and goes on an iPhone, an iPad or an Xbox
    too once it's put there. Lamp plays it in a preview on the Mac to try it.

    ## What it does
    Nothing yet: fresh scaffold, a ball the left stick rolls on a lit floor.

    """

    /// A web game's Package.swift: the Swift around its page, with no library of the game's.
    static let webPackageSwift = """
    // swift-tools-version:5.9
    import PackageDescription

    let package = Package(
        name: "{{EXE}}",
        platforms: [.macOS(.v14), .iOS(.v17)],
        targets: [.executableTarget(name: "{{EXE}}", path: "Sources")]
    )

    """

    /// A web game's build.sh: the Swift around its page for the Mac or the iPhone and iPad simulator, its page copied
    /// into the app (Contents/Resources/Web on the Mac, Web/ at an iOS bundle's top), where the app's web view reads it;
    /// for Android, Lamp's Android app around the page, built by Gradle (`GameAndroid.buildSteps`).
    static var webBuildSh: String {
        webBuildTemplate.replacingOccurrences(of: "@@STAGE@@\n", with: stagePageSh).replacingOccurrences(of: "@@ANDROID@@\n", with: GameAndroid.buildSteps())
    }

    /// build.sh's one way to put the page into what it builds (the Mac's app, the simulator's, Android's assets): Web/,
    /// its files only, with the device it's for beside a game's runtime as Lamp resolved it (`GamePage`, handed over as
    /// LAMP_PAGE_DEVICE), and which build it is (`GamePage.buildFile`). A game's page built without a device stops the
    /// build rather than claim another device's facts.
    static let stagePageSh = """
    stage_page() {
      if find Web -type l | grep -q .; then echo "Web/ holds a shortcut to another file. Put the file itself there." >&2; exit 1; fi
      rm -rf "$1"
      mkdir -p "$(dirname "$1")"
      cp -Rp Web "$1"
      if [ -f "$1/\(GamePage.runtimeFile)" ]; then
        if [ -z "${LAMP_PAGE_DEVICE:-}" ]; then echo "Lamp builds the game, saying which device its page is for: build it from Lamp." >&2; exit 1; fi
        printf '%s' "$LAMP_PAGE_DEVICE" > "$1/\(GamePage.deviceFile)"
        BUILD="$(cd "$1" && find . -type f ! -name \(GamePage.deviceFile) ! -name \(GamePage.buildFile) -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -c1-16)"
        printf '%s"%s";\\n' "\(GamePage.buildPrefix)" "$BUILD" > "$1/\(GamePage.buildFile)"
      fi
    }

    """

    private static let webBuildTemplate = """
    #!/bin/zsh
    # Builds the game for this Mac (./build.sh mac, build/{{EXE}}.app), the iPhone and iPad simulator (./build.sh ios,
    # build/iOS/{{EXE}}.app) or Android (./build.sh android): the Swift around the page, with the page copied in.
    set -euo pipefail
    cd "$(dirname "$0")"
    PLACE="${1:-mac}"
    # dyld ignores DYLD_INSERT_LIBRARIES and the like for a binary with a __RESTRICT segment: the agent's shell can
    # start the installed app, and Lamp answers its secrets calls only to the app itself, so nothing may ride into it.
    mkdir -p .build
    : > .build/restrict
    RESTRICT=(-Xlinker -sectcreate -Xlinker __RESTRICT -Xlinker __restrict -Xlinker "$PWD/.build/restrict")
    @@STAGE@@
    @@ANDROID@@
    if [[ "$PLACE" == "ios" ]]; then
      SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
      FLAGS=(-c debug --triple "$(uname -m)-apple-ios17.0-simulator" --sdk "$SDK" --scratch-path .build/ios)
      APP="build/iOS/{{EXE}}.app"
    else
      FLAGS=(-c release "${RESTRICT[@]}")
      APP="build/{{EXE}}.app"
    fi
    # On this Mac, Lamp's player when Lamp hands it over (LAMP_PLAYER): copied, not compiled, so nothing of Apple's tools runs.
    PLAYER="${LAMP_PLAYER:-}"
    [[ "$PLACE" == "ios" ]] && PLAYER=""
    if [[ -z "$PLAYER" ]]; then
      BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/{{EXE}}"
      swift build "${FLAGS[@]}" 2>&1
    fi
    rm -rf "$APP"
    if [[ "$PLACE" == "ios" ]]; then
      mkdir -p "$APP"
      cp "$BIN" "$APP/{{EXE}}"
      cat > "$APP/Info.plist" <<PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleDevelopmentRegion</key><string>en</string>
      <key>CFBundleExecutable</key><string>{{EXE}}</string>
      <key>CFBundleIdentifier</key><string>{{BUNDLE}}</string>
      <key>CFBundleName</key><string>{{NAME}}</string>
      <key>CFBundleDisplayName</key><string>{{NAME}}</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>0.1</string>
      <key>CFBundleVersion</key><string>1</string>
      <key>LSRequiresIPhoneOS</key><true/>
      <key>MinimumOSVersion</key><string>17.0</string>
      <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
      <key>UILaunchScreen</key><dict/>
      <key>UIRequiresFullScreen</key><true/>
      <key>UIStatusBarHidden</key><true/>
      <key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationLandscapeRight</string><string>UIInterfaceOrientationLandscapeLeft</string></array>
      <key>UISupportedInterfaceOrientations~ipad</key><array><string>UIInterfaceOrientationLandscapeRight</string><string>UIInterfaceOrientationLandscapeLeft</string></array>
      <key>GCSupportsControllerUserInteraction</key><true/>
      <key>GCSupportedGameControllers</key><array><dict><key>ProfileName</key><string>ExtendedGamepad</string></dict></array>
    {{USAGE}}
      <key>DTPlatformName</key><string>iphonesimulator</string>
      <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
    </dict></plist>
    PLIST
    else
      PLAYED=""
      if [[ -n "$PLAYER" ]]; then
        mkdir -p "$(dirname "$APP")"
        cp -Rp "$PLAYER" "$APP"
        mv "$APP/Contents/MacOS/\(playerExe)" "$APP/Contents/MacOS/{{EXE}}"
        PLAYED="<key>LampPlayerVersion</key><string>${LAMP_PLAYER_VERSION:-}</string>"
      else
        mkdir -p "$APP/Contents/MacOS"
        cp "$BIN" "$APP/Contents/MacOS/{{EXE}}"
        # The copy names the SDK it was really built with (see a Mac app's build.sh), so macOS draws it as that SDK does.
        if SDKVER="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)" \\
          && MINOS="$(otool -l "$APP/Contents/MacOS/{{EXE}}" | awk '/minos/ {print $2; exit}')" && [ -n "$MINOS" ]; then
          xcrun vtool -set-build-version macos "$MINOS" "$SDKVER" -replace -output "$APP/Contents/MacOS/{{EXE}}" "$APP/Contents/MacOS/{{EXE}}" >/dev/null 2>&1 || true
        fi
      fi
      cat > "$APP/Contents/Info.plist" <<PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleDevelopmentRegion</key><string>en</string>
      <key>CFBundleExecutable</key><string>{{EXE}}</string>
      <key>CFBundleIdentifier</key><string>{{BUNDLE}}</string>
      <key>CFBundleName</key><string>{{NAME}}</string>
      <key>CFBundleDisplayName</key><string>{{NAME}}</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>0.1</string>
      <key>LSMinimumSystemVersion</key><string>14.0</string>
      <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
      <key>GCSupportsGameMode</key><true/>
    {{MAC_USAGE}}
    {{PLAYER_PLIST}}
      $PLAYED
      <key>NSPrincipalClass</key><string>NSApplication</string>
      <key>NSHighResolutionCapable</key><true/>
    </dict></plist>
    PLIST
    fi
    if [[ "$PLACE" == "ios" ]]; then stage_page "$APP/Web"; else stage_page "$APP/Contents/Resources/Web"; fi
    codesign --force -s - "$APP"
    echo "Built $APP"

    """

    // MARK: Building

    enum Target: String { case xbox, preview }

    /// Runs the kit's build in the app's sandbox, with the tools where Lamp keeps them. The console's build leaves
    /// build/xbox.zip (App.exe and Assets/) for `DeviceApps` to package; the preview's, build/preview/lamp_preview.
    static func build(_ project: LampProject, for target: Target, started: (@MainActor (Process) -> Void)? = nil) async throws {
        if target == .xbox, let problem = WindowsTools.problem { throw Failure(message: problem) }
        try await toolsForApple()
        try write(for: project)
        var printed: [String] = []
        let status = await Sandbox.run("/bin/sh Lamp/build.sh \(target.rawValue)", for: project, env: WindowsTools.buildEnvironment, started: started) { line in
            printed.append(line)
            if printed.count > 400 { printed.removeFirst(200) }
        }
        guard status == 0 else {
            // The compiler's own words, without the source lines it quotes under each.
            let errors = printed.filter { $0.contains("error") || $0.contains("Error") || $0.contains("undefined") }
            let said = (errors.isEmpty ? printed.suffix(30) : errors.prefix(30)).joined(separator: "\n")
            throw Failure(message: "The \(target == .xbox ? "Xbox" : "preview") build failed:\n" + said)
        }
    }

    /// What every build of a game needs beyond the Mac's own tools: sokol-shdc, the shaders' compiler, a small download
    /// fetched the first time with nothing to accept (`WindowsTools.installPreview`).
    @MainActor static func toolsForApple() async throws {
        do { try await WindowsTools.installPreview() } catch {
            throw Failure(message: "Lamp couldn't get the shader compiler games are built with: \(error.localizedDescription)")
        }
    }

    // MARK: The preview

    /// What a play on the preview holds the controller at, for how long: one line of the preview's script.
    struct Hold: Equatable {
        var frames: Int
        var lx: Float = 0, ly: Float = 0, rx: Float = 0, ry: Float = 0, lt: Float = 0, rt: Float = 0
        var buttons: UInt32 = 0

        var line: String {
            func number(_ value: Float) -> String { String(format: "%.3f", max(-1, min(1, value))) }
            return "hold \(frames) \(number(lx)) \(number(ly)) \(number(rx)) \(number(ry)) \(number(lt)) \(number(rt)) \(buttons)"
        }
    }

    /// The controller's buttons by the names the agent uses, as the kit's bits.
    static let buttons: [String: UInt32] = ["a": 1 << 0, "b": 1 << 1, "x": 1 << 2, "y": 1 << 3, "lb": 1 << 4, "rb": 1 << 5,
                                            "menu": 1 << 6, "view": 1 << 7, "up": 1 << 8, "down": 1 << 9, "left": 1 << 10,
                                            "right": 1 << 11, "ls": 1 << 12, "rs": 1 << 13]

    /// The play the agent has made so far in the preview, by app: every look starts one, every `use_app` adds to it,
    /// and each is played again whole from the start (the preview's frames are always 1/60 s and its random numbers
    /// always the same), so a change to the code is seen in the same moves.
    @MainActor static var plays: [String: [String]] = [:]

    /// Where a play's script, saves and pictures are: Lamp's folder in the app, not its runtime folder, which the sandbox
    /// closes when the person keeps what an app shows from the agent (then a play takes no pictures).
    static func previewFolder(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/preview") }

    struct Played {
        var pictures: [URL]
        var printed: [String]
        var stats: String?
        var sound: String?   // what the game played and how loud the mix came out
    }

    /// Plays the script in the preview: the game from its start, saves cleared, pictures where the script says.
    static func play(_ project: LampProject, script given: [String], started: (@MainActor (Process) -> Void)? = nil) async throws -> Played {
        let script = Privacy.sharesPictures ? given : given.filter { !$0.hasPrefix("shot ") }
        let folder = previewFolder(project)
        AppFolder.remove(folder, in: project.dir)
        try AppFolder.write(script.joined(separator: "\n") + "\n", to: folder.appendingPathComponent("script.txt"), in: project.dir)
        try AppFolder.write("", to: folder.appendingPathComponent("saves/.keep"), in: project.dir)
        try AppFolder.write("", to: folder.appendingPathComponent("pictures/.keep"), in: project.dir)
        let here = ".lamp/preview"
        var printed: [String] = []
        let status = await Sandbox.run("build/preview/lamp_preview \(here)/script.txt \(here)/pictures Assets \(here)/saves",
                                       for: project, started: started) { line in
            printed.append(line)
            if printed.count > 600 { printed.removeFirst(300) }
        }
        let stats = printed.last { $0.hasPrefix("Lamp stats:") }
        let sound = printed.last { $0.hasPrefix("Lamp sound:") }
        printed.removeAll { $0.hasPrefix("Lamp stats:") || $0.hasPrefix("Lamp sound:") }
        guard status == 0 else {
            // What it printed is the agent's to read only when the person shares what apps print.
            let said = Privacy.sharesLog && !printed.isEmpty ? " What it printed last:\n" + printed.suffix(20).joined(separator: "\n") : ""
            throw Failure(message: "The game stopped in the preview (exit \(status))." + said)
        }
        let names = script.compactMap { line -> String? in line.hasPrefix("shot ") ? String(line.dropFirst(5)) : nil }
        let pictures = names.map { folder.appendingPathComponent("pictures/\($0).png") }.filter { AppFile.read($0, in: project, last: 1) != nil }
        return Played(pictures: pictures, printed: printed, stats: stats.map { String($0.dropFirst("Lamp stats: ".count)) },
                      sound: sound.map { String($0.dropFirst("Lamp sound: ".count)) })
    }

    // MARK: The web game preview

    /// Where a web game's page is copied for the preview: Lamp's own folder, never the app's, which the agent's
    /// commands can change while the preview reads it.
    static func stagingFolder(_ project: LampProject) -> URL {
        Edition.supportFolder.appendingPathComponent("Game Builds").appendingPathComponent(project.id)
    }

    /// Copies the page out of the app's folder under the app's sandbox, as a TV app's is (`TVs.stage`), refusing one
    /// that holds a link, which would bring what it leads to into the copy.
    static func stageWeb(_ project: LampProject) async throws -> URL {
        let fm = FileManager.default
        let dir = stagingFolder(project), page = dir.appendingPathComponent("web")
        try? fm.removeItem(at: page)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try write(for: project)
        try await compileSource(project)
        let copy = "cd \"$LAMP_FROM\" && /bin/cp -Rp \(Sandbox.quoted(webFolder)) \"$LAMP_TO\""
        guard let confined = Sandbox.wrapEngine(copy, for: project, opening: [dir.path]) else { throw Failure(message: "Lamp couldn't copy the game's files.") }
        var output: [String] = []
        let status = await Shell.run(confined, cwd: dir, env: ["LAMP_FROM": project.dir.path, "LAMP_TO": page.path], login: false) { output.append($0) }
        guard status == 0 else { throw Failure(message: "Lamp couldn't copy the game's files.\n\n" + output.suffix(4).joined(separator: "\n")) }
        let linked = ([page] + (fm.enumerator(at: page, includingPropertiesForKeys: [.isSymbolicLinkKey])?.allObjects as? [URL] ?? []))
            .contains { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true }
        if linked {
            try? fm.removeItem(at: page)
            throw Failure(message: "Web/ holds a shortcut to another file. Put the file itself in its place.")
        }
        guard fm.fileExists(atPath: page.appendingPathComponent("index.html").path) else { throw Failure(message: "The game has no Web/index.html.") }
        // The preview is played on this Mac, so its page is told it's the Mac's.
        try GamePage.stage(page, in: dir, for: GamePage.place(for: project, at: .mac))
        return page
    }

    /// Plays the script on a web game's page, as `play` does on a C++ game's preview, from the copy `stageWeb` made.
    @MainActor static func playWeb(_ project: LampProject, script given: [String]) async throws -> Played {
        let script = Privacy.sharesPictures ? given : given.filter { !$0.hasPrefix("shot ") }
        let page = stagingFolder(project).appendingPathComponent("web")
        guard let (drawn, result) = await WebGamePreview.play(page, script: script) else {
            throw Failure(message: "The game didn't start in the preview, or ran for more than two minutes without finishing the play: "
                + "check that Web/index.html loads it and that game() is called once, and look for an error in what it logged.")
        }
        let logs = result["logs"] as? [String] ?? []
        if let failed = result["failed"] as? String {
            let said = Privacy.sharesLog && !logs.isEmpty ? " What it logged last:\n" + logs.suffix(20).joined(separator: "\n") : ""
            throw Failure(message: "The game stopped in the preview: \(failed)." + said)
        }
        let folder = previewFolder(project)
        AppFolder.remove(folder, in: project.dir)
        var pictures: [URL] = []
        for line in script where line.hasPrefix("shot ") {
            let name = String(line.dropFirst(5))
            guard let png = drawn[name] else { continue }
            let url = folder.appendingPathComponent("pictures/\(name).png")
            try AppFolder.write(png, to: url, in: project.dir)
            pictures.append(url)
        }
        return Played(pictures: pictures, printed: logs, stats: result["stats"] as? String, sound: result["sound"] as? String)
    }

    /// The script for `use_app`'s actions on the controller, or why one can't be played. Each action ends with a picture.
    static func script(for actions: [[String: Any]], startingAt shot: Int) -> (lines: [String], said: [String], problem: String?) {
        var lines: [String] = [], said: [String] = []
        var number = shot
        for action in actions {
            let kind = action["action"] as? String ?? ""
            let seconds = min(max(action["amount"] as? Double ?? (kind == "button" ? 0.1 : 1), 1.0 / 60), 60)
            var hold = Hold(frames: max(1, Int((seconds * 60).rounded())))
            var words: String
            switch kind {
            case "wait":
                words = "waited \(seconds.formatted()) s"
            case "stick":
                let side = (action["target"] as? String ?? "left").lowercased()
                let x = Float(action["x"] as? Double ?? 0), y = Float(action["y"] as? Double ?? 0)
                guard side == "left" || side == "right", abs(x) <= 1, abs(y) <= 1 else {
                    return (lines, said, "A stick is `target` left or right, with x and y from -1 to 1 (up and right positive).")
                }
                if side == "left" { hold.lx = x; hold.ly = y } else { hold.rx = x; hold.ry = y }
                words = "held the \(side) stick at \(x.formatted()), \(y.formatted()) for \(seconds.formatted()) s"
            case "button":
                guard let key = (action["key"] as? String)?.lowercased() else { return (lines, said, "A button action names its button in `key`.") }
                if key == "lt" { hold.lt = 1 } else if key == "rt" { hold.rt = 1 }
                else if let bit = buttons[key] { hold.buttons = bit }
                else { return (lines, said, "\(key) isn't a button: \((buttons.keys.sorted() + ["lt", "rt"]).joined(separator: ", ")).") }
                words = "held \(key.uppercased()) for \(seconds.formatted()) s"
            default:
                return (lines, said, "A game takes `stick`, `button` and `wait`.")
            }
            // A stick moved while a button is held: both at once.
            if kind == "stick", let key = (action["key"] as? String)?.lowercased() {
                if key == "lt" { hold.lt = 1 } else if key == "rt" { hold.rt = 1 } else if let bit = buttons[key] { hold.buttons = bit }
                words += " with \(key.uppercased()) held"
            }
            lines.append(hold.line)
            // Let go before the next action, so a press after a press is a new one.
            if hold != Hold(frames: hold.frames) { lines.append(Hold(frames: 1).line) }
            number += 1
            lines.append("shot \(number)")
            said.append(words.prefix(1).uppercased() + words.dropFirst() + ".")
        }
        return (lines, said, nil)
    }
}

// MARK: - What the builder is told

extension Agent {
    /// The rules for a game. What depends on where it's played (the budget, the places) isn't here but in the request's
    /// device line (`DeviceNote`, `Rules.gamePlaces`), since Claude Code and Codex keep the prompt a conversation began
    /// with, and a place may be given at any time.
    static func gamePrompt(for project: LampProject) -> String {
        let web = GameKit.engine(project) == .web, ownLoop = GameKit.ownsLoop(project)
        // A page made for the Xbox before Lamp's game runtime keeps its own loop, and its own way of being tried.
        let kit = ownLoop ? [Rules.gameOwnLoop] : [web ? Rules.gameWebKit : Rules.gameKit, web ? Rules.gameWebSound : Rules.gameSound] + (web ? [Rules.gameWebLive] : [])
        let rules = [web ? Rules.gameWebEdit : Rules.gameEdit, Rules.ask, Rules.shell] + kit + (web ? [Rules.pageNative] : []) + [Rules.gameBudget, Rules.icon, Rules.about,
                     web ? Rules.gameWebAssets : Rules.gameAssets, ownLoop ? Rules.gameOwnLoopTry : Rules.gameTry, Rules.appMd, Rules.audience,
                     Skills.index(Skills.offered(.game)), Rules.begin, Rules.finish]
        return (Rules.gameHeader + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: "Mac")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a Mac")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "opens it again where Try On points")
    }

    /// The rules for a game that's one of a wish's apps, in a folder of its own: the game's own, for the files there,
    /// without those about the wish as a whole. A game made beside other apps is a page, as every new game is.
    static func gamePrompt(part folder: String, alone: Bool = false) -> String {
        let rules = [Rules.gameWebEdit, Rules.gameWebKit, Rules.gameWebSound, Rules.gameWebLive, Rules.pageNative, Rules.gameBudget, Rules.gameWebAssets,
                     Rules.gameTry, alone ? "" : Rules.gameAmongApps + Rules.wishTalk, Skills.index(Skills.offered(.game))]
        return (Rules.partHeader("a game drawn in a page in Web/ on Lamp's game runtime, at home on the Mac and played on any other device that takes a page (make_app_for's table of devices) once it's put there", folder: folder)
                + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: "Mac")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a Mac")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "opens it again where Try On points")
    }
}

extension Agent.Rules {
    static let gameOwnLoop = """
    - This game's page was made for the Xbox before Lamp had a game runtime: it runs its own loop and reads the controller \
    and keyboard itself. Keep it that way and change what's asked within it. Moving it onto `game()` from Web/lamp-game.js \
    (read all of it first) rewrites its loop, its input and its sound: do that only when the person asks for something \
    that needs it, and once it's done its looks are the preview's scripted plays.

    """

    static let gameOwnLoopTry = """
    - `look_at_app` opens the page in the Xbox preview on this Mac, a 1920x1080 window running it in this Mac's browser, and \
    shows you a picture of it with its screen as text and what its console printed; it's the preview, not the person's \
    Xbox, so never say how it runs on the Xbox itself. `use_app` clicks, types and presses keys there: the arrows, enter, \
    back (Escape), space, a-z and 0-9, with `amount` in seconds to hold one (a game's move), then shows it again. Try it by \
    playing it. `look_at_app` with `on_device` opens it where Try On points (its window on this Mac, or the Xbox) and \
    shows that screen and its log.

    """

    /// How a game's or a screen's places are given while the wish has other apps too: its own word with them, and the
    /// other apps the person keeps, named apart where they're for a device it's also on.
    static func placesAmongApps(_ word: String, verb: String) -> String {
        """

        - This wish has other apps beside the \(word). Where the \(word) is \(verb) is make_app_for's `devices` for it, \
        with its folder in `app` and `made` "web"; the wish's other apps stay as they are, and one is taken away only with remove_app.
        """
    }

    /// For a wish with a game beside other apps: how its places are given, and how it reaches the others.
    static let gameAmongApps = placesAmongApps("game", verb: "played") + """

    - The game reaches the wish's other apps with `Lamp.wish` in Web/lamp.js, the same block a TV app's page has: \
    messages, shared values and files, so another app of the wish can send it moves or things to play with, or show \
    its score. That works wherever it's played: the Mac, an iPhone or an iPad, Android and the Xbox. In Lamp's preview \
    of it `Lamp.wish` is 'away' with a reason saying it can't reach them there, so the game stays whole without them. Its players play with a controller, the keyboard or the touch controls Lamp draws, and \
    phones join as players from its Phone/ page (`Lamp.controllers`); the wish's other apps send it messages rather than \
    joining as players.
    """

    /// For a wish with a screen beside other apps: how its places are given, and how it reaches the others.
    static let screenAmongApps = placesAmongApps("screen", verb: "shown") + """

    - The screen reaches the wish's other apps with `Lamp.wish` in Web/lamp.js, as a TV app does: messages, shared \
    values and files, wherever it's shown, the Xbox included. Lamp's TV preview, where you look at it, joins them only when the screen is shown there, so what \
    another app sends shows where the screen is shown. What every place shows (a list, the calendar, photos) goes in \
    `LampStore.shared` and `LampStore.sharedFiles`, kept the same on every copy of the screen (and with `{ wish: true }` \
    in every app of the wish), with a copy that can read the calendar or the album (on the Mac, an iPhone or an iPad, \
    through `LampNative`) publishing it for the others.
    """

    static let gameHeader = """
    You are Lamp's builder agent. The current directory is a game, which Lamp builds on this Mac. Its home is the Mac, where it's an app the person plays in its own window with the keyboard \
    or a controller; it's played on an iPhone or iPad (touch controls Lamp draws, or a controller), an Android phone, \
    tablet or TV, a Samsung or LG TV (a TV's remote: its arrows and OK) and on the person's Xbox too once it's put there. It's the same code everywhere: the kit gives each place its screen, controls and \
    sound. You try it in a preview on this Mac, the same code drawn out of sight. The request's device line says where \
    it's played and what that allows: never say it's on a device it isn't on. Read APP.md first for context.
    """

    /// What `make_app_for` answers with when an app becomes a game.
    static func gameChange(_ project: LampProject) -> String {
        GameKit.engine(project) == .web ? gameWebEdit + gameWebKit + gameWebSound + gameWebLive + pageNative + gameBudget + gameTry
            : gameEdit + gameKit + gameSound + gameBudget + gameTry
    }

    static var gameWebEdit: String { """
    - The game is a page on Lamp's game runtime, drawn as the game skill says: make the change the user asks for by editing its files in Web/ \
    (index.html, game.js and any other .js modules, and the models, pictures and sounds it loads, beside them). \
    Web/lamp-game.js, Web/lamp-phaser.js, Web/lamp-controllers.js, Web/lamp.js, Web/three/, Web/rapier/ and Web/phaser/ are Lamp's (written before every build), and so are Sources/ but for \
    Sources/Native.swift, build.sh, Package.swift and Lamp/ (the apps around the page): read lamp-game.js, never edit or delete any of them. Lamp \
    builds by itself when you look and, at the end of your turn, opens the game where Try On points (the Mac, a \
    simulator, an Android emulator or device, a TV or the Xbox), so don't run a build, a server or a browser yourself, \
    and leave .lamp/ alone. Where else it's played is the person's to ask for: when they want it somewhere else, call \
    make_app_for with the game's folder in `app` ("." when it's the wish's own folder), `kind` "game", `made` "web" and \
    `devices` every device it's to be played on ("mac", "iphone", "android", "android-tv", "tv", "xbox-one"…: a page \
    goes wherever the table of devices gives a web host); it stays the same game, and the wish's other apps stay as they are.
    """ }

    /// How a page (a web game's, a screen's) reaches what only the app around it can: `LampNative`, answered by the
    /// app's own Swift, and LampAI through the app (LampPage.swift).
    static let pageNative = """
    - The person's own things (their mail, calendar, reminders, contacts, photos, where they are) are read by the app \
    around the page, not by the page: register a call in Sources/Native.swift, yours, inside `Native.register()` \
    (`LampNative.on("unanswered") { args in … }`, Swift returning anything Encodable, with Lamp's building blocks in \
    Sources/LampSupport.swift: LampMail on the Mac, LampCalendar, LampReminders, LampContacts, LampPhotos, \
    LampLocation…; read their doc comments there), and ask for it from the page with \
    `LampNative.call("unanswered", { limit: 30 })`, a Promise of the JSON it returned. Return only what the page \
    shows. AI in the page is LampAI from Web/lamp.js (read it), which reaches Lamp through the app. Both answer only in \
    the app on the Mac, iPhone and iPad (LampAI on Android and the Xbox too): elsewhere, and in Lamp's preview, \
    `LampNative.available` is false and the calls reject, so the page shows example content then, never an error. \
    Make these calls once as it opens or from a menu, never every frame; `look_at_app` with `on_device` shows the \
    real thing. Without Swift of its own the app on the Mac is Lamp's ready-made one, made in a second and with none \
    of Apple's tools; a call registered in Native.swift, or any other Swift in Sources/, makes Lamp compile the app \
    instead, which takes minutes the first time and needs Apple's tools on the person's Mac. So write Swift only for \
    what the page can't reach itself (the person's own things above), never for what the page or Lamp's scripts in \
    Web/ already do.
    """

    static let gameWebKit = """
    - Writing the game: read Web/lamp-game.js first, all of it; it's Lamp's runtime and the whole interface to the \
    device. Choose 2D or 3D from what the person asked for as you begin, then read the game skill and the 2d-game or \
    3d-game skill with `read_skill` before writing any of it: they say what the page draws with, how index.html loads \
    it, how game.js starts the runtime, where the game sets itself up and how each frame runs. index.html loads lamp.js, \
    then the scaffold's import map, then game.js as a module: keep that. The runtime fits the 1920x1080 stage to the \
    window or screen and runs the game's frames about 60 times a second. Never call requestAnimationFrame, setTimeout or \
    setInterval for the game, nor read the clock, Math.random or localStorage: move things by the frame's time and use \
    `random()`, `save(name, value)` and `load(name)` from lamp-game.js, so Lamp's preview replays a play exactly. The \
    controller is the runtime's pad (lx, ly, rx, ry -1 to 1 with up positive and the dead zone out; lt and rt 0 to 1; \
    buttons as BUTTON.A… bits in down, pressed and released; the skill says where a game reads it), the same wherever \
    it's played: a controller connected to the device, the Mac's keyboard (WASD or the arrows the left stick, IJKL the \
    right, Space or Enter A, Esc B, F X, R Y, Q and E the bumpers, Z and C the triggers, P Menu, Tab View) or the touch \
    controls Lamp draws on a phone or tablet (a left stick, and the buttons `touch` names: BUTTON.A | BUTTON.B | \
    BUTTON.MENU unless you say otherwise, BUTTON.RSTICK for a right stick; keep a game playable with those few on a \
    phone). B is the game's, for back or cancel, and Menu for pause. Draw text and menus as HTML over the canvas (a \
    fixed div, large type) or in the game's own drawing; the preview pictures both. \
    The player may hold an Xbox, PlayStation or Switch controller, the keyboard or the touch screen, and switches as \
    they play, so never write a key's or a button's name: write the controls once, as actions mapped to the pad \
    (`const CONTROLS = { jump: BUTTON.A, pause: BUTTON.MENU, move: STICK.LEFT, gas: TRIGGER.RT }`), read the pad \
    through them, and show how to play (the controls as play starts, and a help screen on the title or pause menu) \
    and every prompt from them with lamp-game.js's `label(CONTROLS.jump)` \
    (the words: "A", "✕", "Space") and `glyph(CONTROLS.jump)` (that button's badge as the player's input draws it, an \
    element to put in the text), inside `onInput(draw)`, which draws now and again whenever the player takes up \
    another input (`input()` says which). Both are null where that input has nothing for it: leave that line out. A \
    page that reads the keys itself (`keyboard: false`) names its own keys by their codes, `label('KeyH')`. Shake \
    the controller with `rumble(0, low, high, seconds)`. Log events with `log()`, a line per event, never per \
    frame. Where it's played, the log says every ten seconds how many frames a second it really gets there and at \
    what size it's drawn; when frames run slow, Lamp may draw it smaller and scale it up to the screen (the 3d-game \
    skill says how a game sizes what it draws off-screen then). Plain modern JavaScript, nothing loaded from the network.
    """

    /// How a change goes into the game while it's played (lamp-game.js, "Changes while it's played"; `PageLive`).
    static let gameWebLive = """
    - Your changes go into the game while the person plays it, so write it to keep their place. Give game() (or phaser()) \
    `snapshot()`, returning as plain JSON everything that says where the game is (the mode, which menu or overlay is open, \
    the level, the player's position, heading and speed, what they ride or hold, the camera, the score, lives, time, the \
    time of day…). The new code starts straight there: as the game starts (in init, or the first Phaser scene), \
    `pendingRestore()` from lamp-game.js gives that state, or null for a fresh start, and the game builds exactly that \
    place, with that menu or overlay open and nothing a fresh start would show (no title, intro or tutorial), never \
    starting fresh and then patching it. Keep snapshot() current as you add state, and let the start take a snapshot from \
    before your change (a missing field keeps its start value). Load pictures, models, sounds and \
    data through lamp-game.js (`texture('bricks.png')`, `model('car.glb')`, `sound.load('hit.wav')`, `asset('level.json')`), \
    never by a URL of your own, so a new copy goes into the running game; where the game makes something of its own from \
    a file (a material from shader source, clones of a model, a level from JSON), give game() `assetChanged(path)`, which \
    makes it again and returns true. While a match, race or round is on, `busy()` returns true: a change of code waits \
    for the next pause and the person can press Reload. A change of code with no snapshot starts the game again.
    """

    static let gameWebSound = """
    - Sound: a game has it, through `sound` in lamp-game.js, never an <audio> tag or a library. Give each thing the \
    player does or meets a short effect, under a second: a jump, a hit, a pickup, a menu move, a win. Make them in \
    code with `sound.tone({ wave, from, to, attack, hold, release, volume })` (a square or triangle wave sliding up \
    for a jump or a pickup, down for a fall or a loss, noise for a hit or an explosion, a few milliseconds of attack \
    so nothing clicks) unless the person gave sound files, which go in Web/ and load with `await sound.load('hit.wav')`. \
    Make or load every sound once, as the game sets itself up (the 2d-game or 3d-game skill says where), never during \
    play, then `sound.play(s, { volume, pan, pitch })` as things happen, varying \
    pitch a little (0.9 to 1.1, from random()) for one heard often; `{ loop: true }` for a sound that lasts, changed \
    with `sound.set` and ended with `sound.stop`. Music is optional and quiet (`sound.music(s, 0.35)`) under effects \
    at 0.5 to 0.8. The pause menu (Menu) turns sound and music on and off with `sound.volume(effects, music)`, kept \
    with save(). The preview plays nothing aloud, and each look says what was played.
    """

    static let gameWebAssets = """
    - Files the user attaches are saved in Attachments/, for you to look at; they stay on this Mac. A model, picture \
    or sound the game uses is copied into Web/, which goes into the app, and loaded by its path there through lamp-game.js. \
    Ready-made models, sprite sheets, tilesets and textures come from the `assets` tool, in one style (the assets \
    skill); otherwise shapes and colors made in code: a game of simple shapes, well lit and well colored, looks better \
    than one of mismatched models.
    """

    static let gameEdit = """
    - Make the change the user asks for by editing the game's files: its C++ (.cpp and .h) and shaders (.glsl) in \
    Game/, and what it loads in Assets/. Every .cpp and .glsl in Game/ is built. Lamp/ is Lamp's (the kit, written \
    before every build): read it, never edit or delete it. Lamp builds by itself when you look and, at the end of \
    your turn, puts the game on the Xbox, so don't run the build or reach the console yourself, and leave .lamp/ \
    alone. A game in C++ is played on the Xbox alone: it can't be put anywhere else.
    """

    static let gameKit = """
    - Writing the game: read Lamp/lamp_game.h first, all of it; it's the whole interface. The game is \
    `game_init(const LampSetup*)` and `game_frame(const LampFrame*)`, which draws one frame (sg_begin_pass with \
    `frame->swapchain`, then sg_end_pass and sg_commit) and is called about 60 times a second, always at 1920x1080 \
    (scaled to the window or screen, so lay the game out for that size). Lamp's host makes the device and presents \
    each frame: never present, sleep, wait or loop for time yourself, and move things by `frame->dt`. Draw with \
    sokol_gfx (Lamp/sokol_gfx.h: Metal on Apple's devices, OpenGL ES 3 on Android, D3D11 on the console); shapes from sokol_shape.h (boxes, \
    spheres, cylinders, tori, planes), text with sokol_debugtext.h (on a canvas a third of the screen, so letters are \
    24 px), lines and quick 2D with sokol_gl.h, maths with HandmadeMath.h (right-handed, `HMM_Perspective_RH_ZO`), glTF \
    models with cgltf.h (.glb, read through `lamp_asset` and `cgltf_parse` with the data) and pictures with \
    stb_image.h (`stbi_load_from_memory`). The implementations are compiled in Lamp/lamp_kit.cpp, so include the \
    headers without their IMPLEMENTATION defines. Shaders: one annotated GLSL file per program in Game/ (see \
    Game/scene.glsl and sokol-shdc's @vs/@fs/@program blocks, uniform blocks of vec4 and mat4 only), which Lamp \
    compiles into `<name>.glsl.h` for you to include, and `<name>_shader_desc(sg_query_backend())`. The controller is \
    `frame->pads[0]`: sticks -1 to 1 with up positive and the dead zone already out, triggers 0 to 1, buttons as \
    LAMP_A… bits in `down`, `pressed` and `released`. Every place gives the game that same pad: a controller connected \
    to the device, the Mac's keyboard (WASD or the arrows the left stick, IJKL the right, Space or Return A, Esc B, F X, \
    R Y, Q and E the bumpers, Z and C the triggers, P Menu, Tab View) or the touch controls on a phone or tablet (a \
    left stick, and the buttons `lamp_touch_buttons` names in game_init: A, B and Menu unless you say otherwise; keep \
    a game playable with those few on a phone). B is the game's, for back or cancel, and Menu for pause. Nothing \
    outside the kit: no Windows or Apple headers, no threads, no files but `lamp_asset`, `lamp_save` and `lamp_load`, \
    no network, no rand() or time (use `lamp_random`, so the preview replays the same). Plain C++20 and its standard \
    library are fine.
    """

    static let gameSound = """
    - Sound: a game has it, through the kit (the sound part of lamp_game.h), never anything of the system's. Give \
    each thing the player does or meets a short effect, under a second: a jump, a hit, a pickup, a menu move, a win. \
    Make them in code with `lamp_sound_tone` (a square or triangle wave sliding up for a jump or a pickup, down for a \
    fall or a loss, noise for a hit or an explosion, a few milliseconds of attack so nothing clicks) unless the \
    person gave sound files; theirs go in Assets/ (.wav or .ogg for effects, .ogg or .mp3 for music) and load with \
    `lamp_sound_load`. Load or make every sound once in game_init, then `lamp_play` it as things happen, varying \
    `pitch` a little (0.9 to 1.1, from `lamp_random_float`) for one heard often; `lamp_play_loop` for a sound that \
    lasts (an engine), changed with `lamp_voice_set` and ended with `lamp_stop`. Music is optional and quiet \
    (0.3 to 0.4) under effects at 0.5 to 0.8: `lamp_music` for a file the person gave, or a short tune of your own \
    made into samples (`lamp_sound_samples`, notes of a gentle wave with soft ends) played with `lamp_music_sound`. The pause menu \
    (Menu) turns sound and music on and off with `lamp_volume`, kept with `lamp_save`. The preview plays nothing \
    aloud; each look says what was played and how loud the mix came out: keep its loudest under -3 dB, and play \
    quieter what pushed it over full volume.
    """

    static let gameBudget = """
    - Keep within the means of the slowest place the game is played, which the request's device line names with its \
    budget (draws and vertices a frame, the largest texture): the preview's stats count both. One pass with one or \
    two lights computed in the shader is the safe start; shadow maps and full-screen effects only where the budget \
    allows them. Draw many copies of one mesh as one instanced draw. Make meshes once in game_init, never per frame; \
    allocate nothing per frame. Wherever it's played, the log says every ten seconds how it kept to its frames \
    ("frames … ms on average, slowest … ms"): when frames are late, draw less.
    """

    /// Where a game is played and what that allows, for the request's device line: the weakest place's budget, in
    /// what the preview counts (vertices for C++ on the kit, triangles for a page). The Xbox's is the console the
    /// game goes to, as Device Portal names it: a Series X or S gives a game far more than an Xbox One, whose budget
    /// stands for any console Lamp doesn't know yet.
    static func gamePlaces(_ project: LampProject) -> String {
        gamePlaces(project, xbox: project.openPlaces.contains(.device) ? GameKit.xboxModel(for: project) : nil)
    }

    static func gamePlaces(_ project: LampProject, xbox: String?) -> String {
        let places = project.openPlaces, web = GameKit.engine(project) == .web
        // Slowest first; an iPhone, which has to stay cool on battery, below a Series S.
        var budgets: [(rank: Int, words: String)] = []
        if places.contains(.device) {
            switch xbox {
            case let model? where model.localizedCaseInsensitiveContains("Series X"):
                budgets.append((4, "the person's \(model)'s, which gives a game in Developer Mode most of its GPU" + (web ? ", drawn by its web view" : "") + ": "
                    + (web ? "under about 1,000 draws and 1,000,000 triangles a frame (many copies of one shape as one instanced mesh)" : "under about 1,500 draws and 2,000,000 vertices a frame")
                    + ", textures at most 2048 px, one shadow map and a light post-process pass at most"))
            case let model? where model.localizedCaseInsensitiveContains("Series"):
                budgets.append((3, "the person's \(model)'s, which gives a game in Developer Mode most of its GPU, about a third of a Series X's" + (web ? ", drawn by its web view" : "") + ": "
                    + (web ? "under about 600 draws and 600,000 triangles a frame (many copies of one shape as one instanced mesh)" : "under about 900 draws and 1,200,000 vertices a frame")
                    + ", textures at most 2048 px, one shadow map at most, no post-processing"))
            case let model:
                budgets.append((0, (model.map { "the person's \($0)'s" } ?? "an Xbox One's, the slowest console the game may run on")
                    + ", which gives a game in Developer Mode only part of its GPU: "
                    + (web ? "under about 200 draws and 300,000 triangles a frame, drawn by its web view (many copies of one shape as one instanced mesh), a standard lit material or cheaper, one or two lights" : "under about 300 draws and 500,000 vertices a frame")
                    + ", textures at most 1024 px (keep each model's few), no shadow maps or post-processing beyond a sky gradient"))
            }
        }
        if places.contains(.tv) {
            budgets.append((-2, "a Samsung or LG TV's, whose browser draws 3D far slower than any phone: under about 100 draws and 100,000 triangles a frame, "
                + "textures at most 1024 px, no shadow maps or post-processing, a Lambert material or cheaper"))
        }
        if places.contains(.androidTV) {
            budgets.append((-1, "a Google TV streamer's or a Fire TV stick's, a phone's chip from years ago drawing through its WebView at 1080p: under about 150 draws "
                + "and 150,000 triangles a frame, textures at most 1024 px, no shadow maps or post-processing"))
        }
        if places.contains(.android) {
            budgets.append((1, "a mid-range Android phone's, far slower than an iPhone and drawing through its WebView: under about 300 draws and "
                + (web ? "300,000 triangles" : "500,000 vertices") + " a frame, textures at most 1024 px, no shadow maps"))
        }
        if places.contains(.ios) {
            budgets.append((2, "an iPhone's, which also has to stay cool on battery: under about 600 draws and "
                + (web ? "500,000 triangles" : "1,000,000 vertices") + " a frame, textures at most 2048 px, one shadow map at most"))
        }
        budgets.append((5, "this Mac's, which draws far more than a console: under about 2,000 draws and "
            + (web ? "2,000,000 triangles" : "4,000,000 vertices") + " a frame, textures at most 4096 px; shadows and a post-process pass are fine"))
        let budget = budgets.min { $0.rank < $1.rank }!.words
        return "It's played on \(GameKit.spoken(places).replacingOccurrences(of: "your ", with: "the person's ")), and Try On points at the \(GameKit.placeName(project.destination)) now. "
            + "Its budget is \(budget)."
    }

    static let gameAssets = """
    - Files the user attaches are saved in Attachments/, for you to look at; they stay on this Mac. A model, picture \
    or data file the game uses is copied into Assets/, which goes into the app, and read with \
    `lamp_asset("models/ship.glb")`. Prefer shapes and colors made in code to files: a game of simple shapes, well \
    lit and well colored, looks better than one of mismatched models.
    """

    static let gameTry = """
    - `look_at_app` builds the preview on this Mac and plays the game from its start for two seconds, with no one \
    touching the controller, and shows you the last frame, what the game logged (`lamp_log`, a line per event, never \
    per frame) and the preview's stats (draws a frame, and vertices for C++ or triangles for a page); with `motion` it shows a frame every half \
    second, and what it played on its speakers. `use_app` plays on from there with the controller: `stick` (`target` left or right, `x` and `y` -1 to \
    1, `amount` seconds, optionally `key` held at the same time), `button` (`key` a, b, x, y, lb, rb, lt, rt, menu, \
    view, up, down, left, right, ls, rs; `amount` seconds held, a tap by default) and `wait`, a picture after each. \
    Each look or use plays the whole game again from the start with the same moves, so after a change to the code \
    the same moves show what changed. Play it as the person would before you finish: a game that only looks right \
    isn't done. The preview is this Mac drawing out of sight: it can't show speed, so keep to the budget. \
    `look_at_app` with `on_device` builds the game for where Try On points, opens it there and shows its own picture \
    of the screen and its log: the game's window on this Mac, the iPhone or iPad simulator, or the person's Xbox (its \
    frame times are in its log). Do that once the game plays right in the preview, to see it start where the person \
    plays it. Lamp can't press a real controller, the keys in the person's window or a device's screen: only the \
    person can play it there.
    """
}
