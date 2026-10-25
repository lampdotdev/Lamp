import AppKit
import CryptoKit
import Foundation

/// Games: Lamp's own kind of app (`Platform.game`), a page in `Web/` drawn with three.js and played through Lamp's game
/// runtime (`web/lamp-game.js`) wherever the game has been put (`LampProject.places`). Its home is the Mac: a Mac app in
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

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Whether the app is a game.
    static func isGame(_ project: LampProject) -> Bool { project.platform == .game }

    /// What a game is written for: a page drawn with three.js (`web`, the start for most games: the model writes it
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

    /// The engine a new game is made with: three.js. C++ on the kit is only what games made before three.js games are.
    static func engine(for devices: Set<String>) -> Engine { .web }

    /// The Xbox integration's kind a game goes there as: its web app's for three.js, its game kind's for C++.
    static func xboxKind(for engine: Engine) -> String { engine == .web ? xbox : xboxKind }

    // MARK: Where it's played

    /// The words a game's places are given by, in the naming call's answer and `make_app_for`'s list: "game" itself,
    /// and the devices it's played on.
    static let placeWords: [String: Destination?] = ["game": nil, "screen": nil, "mac": .mac, "iphone": .ios, "ipad": .ios,
                                                     "android": .android, "tv": .tv, xbox: .device, xboxKind: .device, "xbox": .device]

    /// A list of devices that makes a game: "game" with any of its places, or the Xbox's game kind a naming call from
    /// before games were a kind of their own gave.
    static func claims(_ devices: Set<String>) -> Bool {
        // A new game is three.js: the C++ kind's own word ("xbox-one:game") makes nothing new.
        devices.contains("game") && devices.allSatisfy { word in
            word == "game" || (placeWords[word] ?? nil).map(Platform.game.reaches) == true
        }
    }

    /// The places a list of devices gives a kind that takes places one at a time (a game, a screen): always the Mac, its
    /// home, and each other one it names that the kind can be.
    static func places(for devices: Set<String>, of kind: Platform = .game) -> [Destination] {
        let named = Set(devices.compactMap { placeWords[$0] ?? nil })
        // The Mac is a game's and a screen's home, whatever else is listed.
        return kind.target.places.filter { $0 == .mac || named.contains($0) }
    }

    /// The integration a game reaches its Xbox through, when the Xbox is one of its places: worked out from its places,
    /// which meta.json keeps, so setting the places, choosing the kind and a restore all agree.
    static func integration(for project: LampProject) -> String? {
        guard project.openPlaces.contains(.device) else { return nil }
        // A screen goes on the Xbox as its web app; a game as the kind its engine makes.
        return project.platform == .screen ? xbox : xboxKind(for: engine(project))
    }

    /// What a place is called to the person and to the agent.
    static func placeName(_ place: Destination) -> String {
        switch place {
        case .ios: "iPhone and iPad"
        case .android: "Android"
        case .tv: "TV"
        case .device: "Xbox"
        default: "Mac"
        }
    }

    /// The places as the person hears them: "your Mac, your iPhone or iPad and your Xbox".
    static func spoken(_ places: [Destination]) -> String {
        let names = places.map { $0 == .ios ? "your iPhone or iPad" : $0 == .android ? "your Android phone or tablet" : "your " + placeName($0) }
        return names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    /// Whether a folder holds a game: its marker, or the device marker a game made before games were a kind of their
    /// own left, naming the Xbox's game kind.
    static func isMade(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path)
            || DeviceApps.integrationID(in: dir).map { DeviceApps.appKind($0)?.lamp == kind } == true
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
        game.apps = game.apps.map { $0.kind == .device ? WishApp(kind: .game) : $0 }
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

    /// A three.js game's: the Swift around its page, and Lamp's runtime the page plays through.
    static let webFiles: [(path: String, text: String)] = read([("Sources/LampGame.swift", "apple/LampWebGame.swift"),
                                                                 ("\(webFolder)/lamp-game.js", "web/lamp-game.js")])

    /// The bridge between a page and the app around it (a three.js game's and a screen's: LampAI through the app, and
    /// `LampNative` calls of the device), Lamp's; and where those calls are answered, the app's own Swift, written only
    /// when the app has none yet.
    static let page: (path: String, text: String)? = read([("Sources/LampPage.swift", "apple/LampPage.swift")]).first
    static let native: (path: String, text: String)? = read([("Sources/Native.swift", "apple/Native.swift")]).first

    /// Writes the page's bridge, and the app's `Native` when it has none.
    static func writePage(for project: LampProject) throws {
        guard let page, let native else { throw Failure(message: "This copy of Lamp is missing its game kit.") }
        try Template.write(page.text, to: page.path, for: project)
        if !FileManager.default.fileExists(atPath: project.dir.appendingPathComponent(native.path).path) {
            try Template.write(native.text, to: native.path, for: project)
        }
    }

    /// Takes the page's bridge away, with the app's `Native` while it's still the one Lamp wrote: an app that's no
    /// longer a page has no use for either, and its code no longer has what they name.
    static func removePage(from project: LampProject) {
        guard let page, let native else { return }
        AppFolder.remove(project.dir.appendingPathComponent(page.path), in: project.dir)
        let own = project.dir.appendingPathComponent(native.path)
        if (try? String(contentsOf: own, encoding: .utf8)) == native.text { AppFolder.remove(own, in: project.dir) }
    }

    /// Where a three.js game's page is: the folder an Xbox web app keeps its page in, so the game goes on the Xbox as one.
    static let webFolder = "Web"

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
        hasher.update(data: Data((webBuildSh + webPackageSwift).utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined() + "\n"
    }()

    /// Every path Lamp owns in a game, as written in its folder.
    static func paths(for project: LampProject) -> [String] {
        let common = ["Sources/LampSupport.swift", "build.sh", "Package.swift", marker]
        // A C++ game made before three.js games is the kit's alone, played on the Xbox and in the preview.
        guard engine(project) == .web else { return files.map { "\(folder)/\($0.name)" } + ["\(folder)/kit.stamp", marker] }
        return webFiles.map(\.path) + [page?.path ?? "Sources/LampPage.swift", "\(webFolder)/lamp.js"] + DeviceSupport.threeFiles.map { "\(webFolder)/three/\($0.name)" } + common
            + GameAndroid.paths(for: project)
    }

    /// Writes Lamp's files into the game where they differ from what's there (so their dates move only when the kit
    /// changed), and the stamp after them; then the Swift around it and what builds it on Apple's devices.
    static func write(for project: LampProject) throws {
        let engine = engine(project)
        if engine == .web {
            try Template.put(Template.lampSupportSwift(for: project), at: project.dir.appendingPathComponent("Sources/LampSupport.swift"), for: project)
            guard webFiles.count == 2, !DeviceSupport.threeFiles.isEmpty else { throw Failure(message: "This copy of Lamp is missing its game kit.") }
            for file in webFiles { try Template.write(file.text, to: file.path, for: project) }
            try writePage(for: project)
            for file in DeviceSupport.threeFiles(for: project, page: webFolder) {
                try Template.put(file.contents, at: project.dir.appendingPathComponent("\(webFolder)/three/\(file.name)"), for: project)
            }
            // On the Xbox, Lamp's building blocks for its web apps (the controller's keys and rumble in its host); elsewhere
            // the page loads nothing from it.
            // Elsewhere the same blocks, LampAI and LampStore reaching Lamp through the app around the page.
            if project.integration == nil {
                try Template.put(DeviceSupport.webJS, at: project.dir.appendingPathComponent("\(webFolder)/lamp.js"), for: project)
            } else {
                try DeviceSupport.writeDeclared(for: project)
            }
            // On Android too: Lamp's Android app around the page.
            if project.openPlaces.contains(.android) { try GameAndroid.write(for: project) }
            try Template.write(webBuildSh, to: "build.sh", for: project, executable: true)
            try Template.write(webPackageSwift, to: "Package.swift", for: project)
            try Template.write("A game made with Lamp: a page drawn with three.js in Web/.\nengine: web\n", to: marker, for: project)
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
        for path in [folder, "Sources/LampGame.swift", "\(webFolder)/lamp-game.js", "\(webFolder)/three", marker] {
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

    A game built and changed with Lamp: a page in Web/ drawn with three.js and played through Lamp's game runtime
    (Web/lamp-game.js), its models, pictures and sounds beside it. It's a Mac app played in its own window, and goes on
    an iPhone, an iPad or an Xbox too once it's put there. Lamp plays it in a preview on the Mac to try it.

    ## What it does
    Nothing yet: fresh scaffold, a ball the left stick rolls on a lit floor.

    """

    static let appMd = """
    # {{NAME}}

    A game built and changed with Lamp: C++ in Game/ against Lamp's game kit (Lamp/lamp_game.h), with its models,
    pictures and sounds in Assets/. It's a Mac app played in its own window, and goes on an iPhone, an iPad or an Xbox
    too once it's put there. Lamp plays it in a preview on the Mac to try it.

    ## What it does
    Nothing yet: fresh scaffold, a ball the left stick rolls on a lit floor.

    """

    /// A three.js game's Package.swift: the Swift around its page, with no library of the game's.
    static let webPackageSwift = """
    // swift-tools-version:5.9
    import PackageDescription

    let package = Package(
        name: "{{EXE}}",
        platforms: [.macOS(.v14), .iOS(.v17)],
        targets: [.executableTarget(name: "{{EXE}}", path: "Sources")]
    )

    """

    /// A three.js game's build.sh: the Swift around its page for the Mac or the iPhone and iPad simulator, its page copied
    /// into the app (Contents/Resources/Web on the Mac, Web/ at an iOS bundle's top), where the app's web view reads it;
    /// for Android, Lamp's Android app around the page, built by Gradle (`GameAndroid.buildSteps`).
    static var webBuildSh: String { webBuildTemplate.replacingOccurrences(of: "@@ANDROID@@\n", with: GameAndroid.buildSteps()) }

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
    @@ANDROID@@
    if [[ "$PLACE" == "ios" ]]; then
      SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
      FLAGS=(-c debug --triple "$(uname -m)-apple-ios17.0-simulator" --sdk "$SDK" --scratch-path .build/ios)
      APP="build/iOS/{{EXE}}.app"
    else
      FLAGS=(-c release "${RESTRICT[@]}")
      APP="build/{{EXE}}.app"
    fi
    BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/{{EXE}}"
    swift build "${FLAGS[@]}" 2>&1
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
      <key>DTPlatformName</key><string>iphonesimulator</string>
      <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
    </dict></plist>
    PLIST
    else
      mkdir -p "$APP/Contents/MacOS"
      cp "$BIN" "$APP/Contents/MacOS/{{EXE}}"
      # The copy names the SDK it was really built with (see a Mac app's build.sh), so macOS draws it as that SDK does.
      if SDKVER="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)" \\
        && MINOS="$(otool -l "$APP/Contents/MacOS/{{EXE}}" | awk '/minos/ {print $2; exit}')" && [ -n "$MINOS" ]; then
        xcrun vtool -set-build-version macos "$MINOS" "$SDKVER" -replace -output "$APP/Contents/MacOS/{{EXE}}" "$APP/Contents/MacOS/{{EXE}}" >/dev/null 2>&1 || true
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
      <key>NSPrincipalClass</key><string>NSApplication</string>
      <key>NSHighResolutionCapable</key><true/>
    </dict></plist>
    PLIST
    fi
    # The page, its files only: a link in it would bring what it leads to into the app.
    if find Web -type l | grep -q .; then echo "Web/ holds a shortcut to another file. Put the file itself there." >&2; exit 1; fi
    if [[ "$PLACE" == "ios" ]]; then WEB="$APP/Web"; else WEB="$APP/Contents/Resources/Web"; mkdir -p "$APP/Contents/Resources"; fi
    rm -rf "$WEB"
    cp -R Web "$WEB"
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

    // MARK: The three.js preview

    /// Where a three.js game's page is copied for the preview: Lamp's own folder, never the app's, which the agent's
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
        return page
    }

    /// Plays the script on a three.js game's page, as `play` does on a C++ game's preview, from the copy `stageWeb` made.
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
        let web = GameKit.engine(project) == .web
        let rules = [web ? Rules.gameWebEdit : Rules.gameEdit, Rules.ask, Rules.shell, web ? Rules.gameWebKit : Rules.gameKit,
                     web ? Rules.gameWebSound : Rules.gameSound] + (web ? [Rules.pageNative] : []) + [Rules.gameBudget, Rules.icon, Rules.about,
                     web ? Rules.gameWebAssets : Rules.gameAssets, Rules.gameTry, Rules.appMd, Rules.audience, Rules.begin, Rules.finish]
        return (Rules.gameHeader + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: "Mac")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a Mac")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "opens it again where Try On points")
    }

    /// The rules for a game that's one of a wish's apps, in a folder of its own: the game's own, for the files there,
    /// without those about the wish as a whole. A game made beside other apps is three.js, as every new game is.
    static func gamePrompt(part folder: String, alone: Bool = false) -> String {
        let rules = [Rules.gameWebEdit, Rules.gameWebKit, Rules.gameWebSound, Rules.pageNative, Rules.gameBudget, Rules.gameWebAssets,
                     Rules.gameTry, alone ? "" : Rules.gameAmongApps]
        return (Rules.partHeader("a game drawn with three.js in Web/, at home on the Mac and played on an iPhone or iPad, an Android phone and an Xbox too once it's put there", folder: folder)
                + "\n\nRules:\n" + rules.joined())
            // Beside other apps the list names the game too, and the apps it keeps (`placesAmongApps`).
            .replacingOccurrences(of: #"(["mac", "iphone"], ["mac", "android"], ["mac", "xbox-one"]…)"#, with: #"(["game", "iphone"], with the wish's other apps)"#)
            .replacingOccurrences(of: "{{DEVICE}}", with: "Mac")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a Mac")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "opens it again where Try On points")
    }
}

extension Agent.Rules {
    /// How a game's or a screen's places are given while the wish has other apps too: its own word with them, and the
    /// other apps the person keeps, named apart where they're for a device it's also on.
    static func placesAmongApps(_ word: String, verb: String) -> String {
        """

        - This wish has other apps beside the \(word). Where the \(word) is \(verb) and which apps the wish has are         both given with make_app_for, in one list: "\(word)" with its places, and every other app the person keeps.         A device it's \(verb) on that has an app of its own too is written with "app" after it ("mac app",         "iphone app", "android app"), so ["\(word)", "iphone", "mac app"] is the \(word) \(verb) on the Mac and the         iPhone with the Mac app beside it. An app left out of the list is taken away.
        """
    }

    /// For a wish with a game beside other apps: how its places are given, and what its other apps can't do with it.
    static let gameAmongApps = placesAmongApps("game", verb: "played") + """

    - The wish's game doesn't send or get messages from its other apps yet: it has no `Lamp.wish` and no     `Lamp.controllers`, and its players use a controller, the keyboard or the touch controls Lamp draws. Don't write     another app of the wish to steer it or share data with it; say so if the person asks for that.
    """

    static let gameHeader = """
    You are Lamp's builder agent. The current directory is a game, which Lamp builds on this Mac. Its home is the Mac, where it's an app the person plays in its own window with the keyboard \
    or a controller; it's played on an iPhone or iPad (touch controls Lamp draws, or a controller), an Android phone or \
    tablet and on the person's Xbox too once it's put there. It's the same code everywhere: the kit gives each place its screen, controls and \
    sound. You try it in a preview on this Mac, the same code drawn out of sight. The request's device line says where \
    it's played and what that allows: never say it's on a device it isn't on. Read APP.md first for context.
    """

    /// What `make_app_for` answers with when an app becomes a game.
    static func gameChange(_ project: LampProject) -> String {
        GameKit.engine(project) == .web ? gameWebEdit + gameWebKit + gameWebSound + pageNative + gameBudget + gameTry
            : gameEdit + gameKit + gameSound + gameBudget + gameTry
    }

    static let gameWebEdit = """
    - The game is a page drawn with three.js: make the change the user asks for by editing its files in Web/ \
    (index.html, game.js and any other .js modules, and the models, pictures and sounds it loads, beside them). \
    Web/lamp-game.js, Web/lamp.js and Web/three/ are Lamp's (written before every build), and so are Sources/ but for \
    Sources/Native.swift, build.sh, Package.swift and Lamp/ (the apps around the page): read lamp-game.js, never edit or delete any of them. Lamp \
    builds by itself when you look and, at the end of your turn, opens the game where Try On points (the Mac, a \
    simulator or the Xbox), so don't run a build, a server or a browser yourself, and leave .lamp/ alone. Where else \
    it's played is the person's to ask for: when they want it on their iPhone, iPad, Android phone or Xbox, call \
    make_app_for with every place it's to be played (["mac", "iphone"], ["mac", "android"], ["mac", "xbox-one"]…); it \
    stays the same game.
    """

    /// How a page (a three.js game's, a screen's) reaches what only the app around it can: `LampNative`, answered by the
    /// app's own Swift, and LampAI through the app (LampPage.swift).
    static let pageNative = """
    - The person's own things (their mail, calendar, reminders, contacts, photos, where they are) are read by the app \
    around the page, not by the page: register a call in Sources/Native.swift, yours, inside `Native.register()` \
    (`LampNative.on("unanswered") { args in … }`, Swift returning anything Encodable, with Lamp's building blocks in \
    Sources/LampSupport.swift: LampMail on the Mac, LampCalendar, LampReminders, LampContacts, LampPhotos, \
    LampLocation…; read their doc comments there), and ask for it from the page with \
    `LampNative.call("unanswered", { limit: 30 })`, a Promise of the JSON it returned. Return only what the page \
    shows. AI in the page is LampAI from Web/lamp.js (read it), which reaches Lamp through the app. Both answer only in \
    the app on the Mac, iPhone and iPad (LampAI on the Xbox too): elsewhere, and in Lamp's preview, \
    `LampNative.available` is false and the calls reject, so the page shows example content then, never an error. \
    Make these calls once as it opens or from a menu, never every frame; `look_at_app` with `on_device` shows the \
    real thing.
    """

    static let gameWebKit = """
    - Writing the game: read Web/lamp-game.js first, all of it; it's Lamp's runtime and the whole interface to the \
    device. index.html loads lamp.js, then the import map for three.js (`three` and `three/addons/`, from Web/three: \
    the WebGL build and its addons such as GLTFLoader; `three/webgpu` and `three/tsl`, node materials drawing with \
    WebGL 2, are added once the page imports them, and only a heavy scene needs them; nothing else is there, so no \
    Draco or KTX2 files), then \
    game.js as a module: keep that. game.js makes a `THREE.WebGLRenderer({ antialias: true })` and calls \
    `game({ renderer, init, frame, touch })` once: Lamp sizes the canvas to 1920x1080 and fits it to the window or \
    screen, runs `init` once (it may be async, to load models with `GLTFLoader().loadAsync('ship.glb')` or sounds), \
    then `frame(f)` about 60 times a second, which moves things by `f.dt` and ends with `renderer.render(scene, \
    camera)`. Never call requestAnimationFrame, setTimeout or setInterval for the game, nor read the clock, \
    Math.random or localStorage: use `f.dt`, `f.time`, `random()`, `save(name, value)` and `load(name)` from \
    lamp-game.js, so Lamp's preview replays a play exactly. The controller is `f.pads[0]` (lx, ly, rx, ry -1 to 1 \
    with up positive and the dead zone out; lt and rt 0 to 1; buttons as BUTTON.A… bits in down, pressed and \
    released), the same wherever it's played: a controller connected to the device, the Mac's keyboard (WASD or the \
    arrows the left stick, IJKL the right, Space or Enter A, Esc B, F X, R Y, Q and E the bumpers, Z and C the \
    triggers, P Menu, Tab View) or the touch controls Lamp draws on a phone or tablet (a left stick, and the buttons \
    `touch` names: BUTTON.A | BUTTON.B | BUTTON.MENU unless you say otherwise, BUTTON.RSTICK for a right stick; keep \
    a game playable with those few on a phone). B is the game's, for back or cancel, and Menu for pause. Draw text \
    and menus as HTML over the canvas (a fixed div, large type) or into the scene; the preview pictures both. Shake \
    the controller with `rumble(0, low, high, seconds)`. Log events with `log()`, a line per event, never per \
    frame. Plain modern JavaScript, nothing loaded from the network.
    """

    static let gameWebSound = """
    - Sound: a game has it, through `sound` in lamp-game.js, never an <audio> tag or a library. Give each thing the \
    player does or meets a short effect, under a second: a jump, a hit, a pickup, a menu move, a win. Make them in \
    code with `sound.tone({ wave, from, to, attack, hold, release, volume })` (a square or triangle wave sliding up \
    for a jump or a pickup, down for a fall or a loss, noise for a hit or an explosion, a few milliseconds of attack \
    so nothing clicks) unless the person gave sound files, which go in Web/ and load with `await sound.load('hit.wav')`. \
    Make or load every sound once in init, then `sound.play(s, { volume, pan, pitch })` as things happen, varying \
    pitch a little (0.9 to 1.1, from random()) for one heard often; `{ loop: true }` for a sound that lasts, changed \
    with `sound.set` and ended with `sound.stop`. Music is optional and quiet (`sound.music(s, 0.35)`) under effects \
    at 0.5 to 0.8. The pause menu (Menu) turns sound and music on and off with `sound.volume(effects, music)`, kept \
    with save(). The preview plays nothing aloud, and each look says what was played.
    """

    static let gameWebAssets = """
    - Files the user attaches are saved in Attachments/, for you to look at; they stay on this Mac. A model, picture \
    or sound the game uses is copied into Web/, which goes into the app, and loaded by its path there. Prefer shapes \
    and colours made in code to files: a game of simple shapes, well lit and well coloured, looks better than one of \
    mismatched models.
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
    /// what the preview counts (vertices for C++ on the kit, triangles for three.js).
    static func gamePlaces(_ project: LampProject) -> String {
        let places = project.openPlaces, web = GameKit.engine(project) == .web
        let budget: String
        if places.contains(.device) {
            budget = "an Xbox One's, the slowest console the game may run on, which gives a game in Developer Mode only part of its GPU: "
                + (web ? "under about 200 draws and 300,000 triangles a frame, drawn by its web view (many copies of one shape as one THREE.InstancedMesh), MeshStandardMaterial or cheaper, one or two lights" : "under about 300 draws and 500,000 vertices a frame")
                + ", textures at most 1024 px (keep each model's few), no shadow maps or post-processing beyond a sky gradient"
        } else if places.contains(.android) {
            budget = "a mid-range Android phone's, far slower than an iPhone and drawing through its WebView: under about 300 draws and "
                + (web ? "300,000 triangles" : "500,000 vertices") + " a frame, textures at most 1024 px, no shadow maps"
        } else if places.contains(.ios) {
            budget = "an iPhone's, which also has to stay cool on battery: under about 600 draws and "
                + (web ? "500,000 triangles" : "1,000,000 vertices") + " a frame, textures at most 2048 px, one shadow map at most"
        } else {
            budget = "this Mac's, which draws far more than a console: under about 2,000 draws and "
                + (web ? "2,000,000 triangles" : "4,000,000 vertices") + " a frame, textures at most 4096 px; shadows and a post-process pass are fine"
        }
        return "It's played on \(GameKit.spoken(places).replacingOccurrences(of: "your ", with: "the person's ")), and Try On points at the \(GameKit.placeName(project.destination)) now. "
            + "Its budget is \(budget)."
    }

    static let gameAssets = """
    - Files the user attaches are saved in Attachments/, for you to look at; they stay on this Mac. A model, picture \
    or data file the game uses is copied into Assets/, which goes into the app, and read with \
    `lamp_asset("models/ship.glb")`. Prefer shapes and colours made in code to files: a game of simple shapes, well \
    lit and well coloured, looks better than one of mismatched models.
    """

    static let gameTry = """
    - `look_at_app` builds the preview on this Mac and plays the game from its start for two seconds, with no one \
    touching the controller, and shows you the last frame, what the game logged (`lamp_log`, a line per event, never \
    per frame) and the preview's stats (draws a frame, and vertices for C++ or triangles for three.js); with `motion` it shows a frame every half \
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
