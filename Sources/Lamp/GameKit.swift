import AppKit
import CryptoKit
import Foundation

/// Games: Lamp's own kind of app (`Platform.game`), C++ written once against Lamp's game kit (`lamp_game.h`: sokol_gfx
/// for drawing, with sokol's shapes and text, HandmadeMath, cgltf and stb_image, and the kit's own sound mix with
/// stb_vorbis, dr_wav and dr_mp3) and played wherever the game has been put (`LampProject.places`). Its home is the
/// Mac: a Mac app in the person's Apps like any other, the game drawn with Metal in its window by the kit's Apple host
/// (`lamp_apple.mm`) inside a little Swift of Lamp's own (`LampGame.swift`, with LampSupport.swift, so it has the wand,
/// the chat beside it and everything else a Lamp app does). The same code goes on an iPhone or iPad through that host,
/// with touch controls, and on the Xbox through the console's host (`lamp_xbox.cpp`), compiled on this Mac with LLVM
/// and Microsoft's SDK (`WindowsTools`) into an x64 app Lamp packages itself (`MSIX`) and puts on the console through
/// its integration's bridge, as the Xbox's web apps go (the integration's `kinds.game` is that package's kind).
///
/// Wherever it's played, the agent plays it in a preview on the Mac (the same code drawn with Metal, out of sight, from
/// a script of the controller's moves: `play`), so its looks are the same frames every time.
///
/// The game's folder: `Game/` (the agent's .cpp, .h and .glsl), `Assets/` (models, pictures, sounds the game reads with
/// `lamp_asset`), and Lamp's, written before every turn and build and never the agent's: `Lamp/` (the kit and its
/// hosts), `Sources/` (the Swift around it on Apple's devices), `build.sh`, `Package.swift` and `.lamp-game`, which
/// marks the folder as a game's; and `build/`.
enum GameKit {
    static let kind = "native-game"
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

    // MARK: Where it's played

    /// The words a game's places are given by, in the naming call's answer and `make_app_for`'s list: "game" itself,
    /// and the devices it's played on.
    static let placeWords: [String: Destination?] = ["game": nil, "mac": .mac, "iphone": .ios, "ipad": .ios,
                                                     xbox: .device, xboxKind: .device, "xbox": .device]

    /// A list of devices that makes a game: "game" with any of its places, or the Xbox's game kind a naming call from
    /// before games were a kind of their own gave.
    static func claims(_ devices: Set<String>) -> Bool {
        (devices.contains("game") || devices.contains(xboxKind)) && devices.allSatisfy { placeWords.keys.contains($0) }
    }

    /// The places a list of devices gives a game: always the Mac, its home, and each other one it names.
    static func places(for devices: Set<String>) -> [Destination] {
        let named = Set(devices.compactMap { placeWords[$0] ?? nil })
        return [.mac, .ios, .device].filter { $0 == .mac || named.contains($0) }
    }

    /// What a place is called to the person and to the agent.
    static func placeName(_ place: Destination) -> String {
        switch place {
        case .ios: "iPhone and iPad"
        case .device: "Xbox"
        default: "Mac"
        }
    }

    /// The places as the person hears them: "your Mac, your iPhone or iPad and your Xbox".
    static func spoken(_ places: [Destination]) -> String {
        let names = places.map { $0 == .ios ? "your iPhone or iPad" : "your " + placeName($0) }
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
        game.places = [.mac, .device]
        game.chosen = .device
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

    /// The Swift around the game on Apple's devices, and the C declarations it calls the host by, as written in the
    /// game's folder.
    static let appleFiles: [(path: String, text: String)] = {
        guard let apple = resources?.appendingPathComponent("apple") else { return [] }
        return [("Sources/LampGame.swift", "LampGame.swift"), ("\(folder)/host/include/lamp_apple.h", "host/include/lamp_apple.h"),
                ("\(folder)/host/lamp_bridge.c", "host/lamp_bridge.c")].compactMap { path, from in
            (try? String(contentsOf: apple.appendingPathComponent(from), encoding: .utf8)).map { (path, $0) }
        }
    }()

    /// Names every file of the kit's by its contents, so the build compiles Lamp's code again only when it changed, and
    /// a game is built again when Lamp's part of it changed (`Target.Recipe.inputs`).
    static let stamp: String = {
        var hasher = SHA256()
        for file in files { hasher.update(data: Data(file.name.utf8)); hasher.update(data: file.data) }
        // And the app around it on Apple's devices, which a new Lamp may change while the kit stays as it was.
        for file in appleFiles { hasher.update(data: Data((file.path + file.text).utf8)) }
        hasher.update(data: Data((buildSh + packageSwift).utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined() + "\n"
    }()

    /// Every path Lamp owns in a game, as written in its folder.
    static var paths: [String] {
        files.map { "\(folder)/\($0.name)" } + ["\(folder)/kit.stamp"] + appleFiles.map(\.path)
            + ["Sources/LampSupport.swift", "build.sh", "Package.swift", marker]
    }

    /// Writes Lamp's files into the game where they differ from what's there (so their dates move only when the kit
    /// changed), and the stamp after them; then the Swift around it and what builds it on Apple's devices.
    static func write(for project: LampProject) throws {
        guard !files.isEmpty, appleFiles.count == 3 else { throw Failure(message: "This copy of Lamp is missing its game kit.") }
        for file in files {
            try Template.put(file.data, at: project.dir.appendingPathComponent("\(folder)/\(file.name)"), for: project)
        }
        try Template.put(stamp, at: project.dir.appendingPathComponent("\(folder)/kit.stamp"), for: project)
        for file in appleFiles { try Template.write(file.text, to: file.path, for: project) }
        try Template.put(Template.lampSupportSwift(for: project), at: project.dir.appendingPathComponent("Sources/LampSupport.swift"), for: project)
        try Template.write(buildSh, to: "build.sh", for: project, executable: true)
        try Template.write(packageSwift, to: "Package.swift", for: project)
        try Template.write("A game made with Lamp: C++ in Game/ against Lamp's game kit in Lamp/.\n", to: marker, for: project)
        // A game made before games were a kind of their own was marked as a device app's.
        if DeviceApps.isScaffolded(project.dir) { AppFolder.remove(project.dir.appendingPathComponent(DeviceApps.marker), in: project.dir) }
    }

    /// Takes Lamp's game files out of an app that's no longer a game, so its next kind builds without them; the
    /// game's own code in Game/ is the agent's to move and delete.
    static func remove(from project: LampProject) {
        for path in [folder, "Sources/LampGame.swift", marker] { AppFolder.remove(project.dir.appendingPathComponent(path), in: project.dir) }
    }

    /// The scaffold: a game that already draws and moves, for the agent to make into the one asked for.
    static func fill(_ project: LampProject) throws {
        guard let resources else { throw Failure(message: "This copy of Lamp is missing its game kit.") }
        let scaffold = resources.appendingPathComponent("scaffold")
        for path in ["Game/game.cpp", "Game/scene.glsl"] {
            let text = try String(contentsOf: scaffold.appendingPathComponent(path), encoding: .utf8)
            try Template.write(text, to: path, for: project)
        }
        try Template.write("Models, pictures and sounds the game reads with lamp_asset(\"name\") go in this folder.\n", to: "Assets/README.txt", for: project)
        try Template.write(".lamp/\n.build/\nbuild/\n", to: ".gitignore", for: project)
        try Template.write(appMd, to: "APP.md", for: project)
        try write(for: project)
    }

    /// Whether the game is still the scaffold: its code is as Lamp wrote it.
    static func isScaffold(_ project: LampProject) -> Bool {
        guard let scaffold = resources?.appendingPathComponent("scaffold/Game/game.cpp"),
              let written = try? String(contentsOf: scaffold, encoding: .utf8),
              let now = AppFile.text(project.dir.appendingPathComponent("Game/game.cpp"), in: project) else { return false }
        return now == written.replacingOccurrences(of: "{{NAME}}", with: project.name)
    }

    static let appMd = """
    # {{NAME}}

    A game built and changed with Lamp: C++ in Game/ against Lamp's game kit (Lamp/lamp_game.h), with its models,
    pictures and sounds in Assets/. It's a Mac app played in its own window, and goes on an iPhone, an iPad or an Xbox
    too once it's put there. Lamp plays it in a preview on the Mac to try it.

    ## What it does
    Nothing yet: fresh scaffold, a ball the left stick rolls on a lit floor.

    """

    /// Package.swift: the Swift around the game, for the Mac and for iOS, with the host's C declarations as a module of
    /// its own. The game itself is the library build.sh makes and links in.
    static let packageSwift = """
    // swift-tools-version:5.9
    import PackageDescription

    let package = Package(
        name: "{{EXE}}",
        platforms: [.macOS(.v14), .iOS(.v17)],
        targets: [
            .target(name: "LampGameHost", path: "Lamp/host"),
            .executableTarget(name: "{{EXE}}", dependencies: ["LampGameHost"], path: "Sources", sources: ["LampGame.swift", "LampSupport.swift"],
                              linkerSettings: [.linkedLibrary("c++"), .linkedFramework("Metal"), .linkedFramework("QuartzCore"),
                                               .linkedFramework("AVFoundation"), .linkedFramework("GameController"),
                                               .linkedFramework("CoreHaptics", .when(platforms: [.iOS]))]),
        ]
    )

    """

    /// build.sh: the game for the Mac (`./build.sh mac`, build/{{EXE}}.app) or the iPhone and iPad simulator
    /// (`./build.sh ios`, build/iOS/{{EXE}}.app). The game, the kit and its host are compiled into one library first
    /// (Lamp/build.sh), then the Swift around it is built and linked with it, and wrapped as an app.
    static let buildSh = """
    #!/bin/zsh
    # Builds build/{{EXE}}.app for this Mac (./build.sh mac) or build/iOS/{{EXE}}.app for the iPhone and iPad simulator (./build.sh ios).
    set -euo pipefail
    cd "$(dirname "$0")"
    PLACE="${1:-mac}"
    # dyld ignores DYLD_INSERT_LIBRARIES and the like for a binary with a __RESTRICT segment: the agent's shell can
    # start the installed app, and Lamp answers its secrets calls only to the app itself, so nothing may ride into it.
    mkdir -p .build
    : > .build/restrict
    RESTRICT=(-Xlinker -sectcreate -Xlinker __RESTRICT -Xlinker __restrict -Xlinker "$PWD/.build/restrict")
    if [[ "$PLACE" == "ios" ]]; then
      sh Lamp/build.sh ios-sim
      SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
      FLAGS=(-c debug --triple "$(uname -m)-apple-ios17.0-simulator" --sdk "$SDK" --scratch-path .build/ios -Xlinker "$PWD/build/ios-sim/libgame.a")
      APP="build/iOS/{{EXE}}.app"
    else
      sh Lamp/build.sh mac
      FLAGS=(-c release "${RESTRICT[@]}" -Xlinker "$PWD/build/mac/libgame.a")
      APP="build/{{EXE}}.app"
    fi
    LIB="build/$([[ "$PLACE" == "ios" ]] && echo ios-sim || echo mac)/libgame.a"
    BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/{{EXE}}"
    # SwiftPM links again only for its own inputs: the game's library is new, so the program is linked again.
    if [ -f "$BIN" ] && [ "$LIB" -nt "$BIN" ]; then rm -f "$BIN"; fi
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
                return (lines, said, "An Xbox game takes `stick`, `button` and `wait`.")
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
        let rules = [Rules.gameEdit, Rules.ask, Rules.shell, Rules.gameKit, Rules.gameSound, Rules.gameBudget, Rules.icon, Rules.about,
                     Rules.gameAssets, Rules.gameTry, Rules.appMd, Rules.audience, Rules.begin, Rules.finish]
        return (Rules.gameHeader + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: "Mac")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a Mac")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "opens it again where Try On points")
    }
}

extension Agent.Rules {
    static let gameHeader = """
    You are Lamp's builder agent. The current directory is a game: C++ written against Lamp's game kit, which Lamp \
    builds on this Mac. Its home is the Mac, where it's an app the person plays in its own window with the keyboard \
    or a controller; it's played on an iPhone or iPad (touch controls Lamp draws, or a controller) and on the person's \
    Xbox too once it's put there. It's the same code everywhere: the kit gives each place its screen, controls and \
    sound. You try it in a preview on this Mac, the same code drawn out of sight. The request's device line says where \
    it's played and what that allows: never say it's on a device it isn't on. Read APP.md first for context.
    """

    /// What `make_app_for` answers with when an app becomes a game.
    static let gameChange = gameEdit + gameKit + gameSound + gameBudget + gameTry

    static let gameEdit = """
    - Make the change the user asks for by editing the game's files: its C++ (.cpp and .h) and shaders (.glsl) in \
    Game/, and what it loads in Assets/. Every .cpp and .glsl in Game/ is built. Lamp/, Sources/, build.sh and \
    Package.swift are Lamp's (the kit and the app around the game, written before every build): read Lamp/, never \
    edit or delete any of them. Lamp builds by itself when you look and, at the end of your turn, opens the game \
    where Try On points (the Mac, a simulator or the Xbox), so don't run the build or reach a device yourself, and \
    leave .lamp/ alone. Where else it's played is the person's to ask for: when they want it on their iPhone, iPad or \
    Xbox, call make_app_for with every place it's to be played (["mac", "iphone"], ["mac", "xbox-one"]…); it stays the \
    same game.
    """

    static let gameKit = """
    - Writing the game: read Lamp/lamp_game.h first, all of it; it's the whole interface. The game is \
    `game_init(const LampSetup*)` and `game_frame(const LampFrame*)`, which draws one frame (sg_begin_pass with \
    `frame->swapchain`, then sg_end_pass and sg_commit) and is called about 60 times a second, always at 1920x1080 \
    (scaled to the window or screen, so lay the game out for that size). Lamp's host makes the device and presents \
    each frame: never present, sleep, wait or loop for time yourself, and move things by `frame->dt`. Draw with \
    sokol_gfx (Lamp/sokol_gfx.h: Metal on Apple's devices, D3D11 on the console); shapes from sokol_shape.h (boxes, \
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
    R Y, Q and E the bumpers, Z and C the triggers, P Menu, Tab View) or the touch controls on an iPhone or iPad (a \
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

    /// Where a game is played and what that allows, for the request's device line: the weakest place's budget.
    static func gamePlaces(_ project: LampProject) -> String {
        let places = project.openPlaces
        let budget: String
        if places.contains(.device) {
            budget = "an Xbox One's, the slowest console the game may run on, which gives a game in Developer Mode only part of its GPU: under about 300 draws and 500,000 vertices a frame, textures at most 1024 px (keep each model's few), no shadow maps or post-processing beyond a sky gradient"
        } else if places.contains(.ios) {
            budget = "an iPhone's, which also has to stay cool on battery: under about 600 draws and 1,000,000 vertices a frame, textures at most 2048 px, one shadow map at most"
        } else {
            budget = "this Mac's, which draws far more than a console: under about 2,000 draws and 4,000,000 vertices a frame, textures at most 4096 px; shadows and a post-process pass are fine"
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
    per frame) and the preview's stats (draws and vertices a frame); with `motion` it shows a frame every half \
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
