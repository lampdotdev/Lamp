import AppKit
import CryptoKit
import Foundation

/// Native 3D games for the Xbox: Lamp's own kind of app ("native-game"), which the Xbox's integration offers beside
/// its web app (`Integration.kinds`, "xbox-one:game"). The game is C++ written against Lamp's game kit (`lamp_game.h`:
/// sokol_gfx for drawing, with sokol's shapes and text, HandmadeMath, cgltf and stb_image, and the kit's own sound mix
/// with stb_vorbis, dr_wav and dr_mp3), compiled on this Mac for
/// the console with LLVM and Microsoft's SDK (`WindowsTools`) into an x64 app Lamp packages itself (`MSIX`), and put
/// on the Xbox through its integration's bridge like the web app is.
///
/// A data-declared kind can't hold this: the kit's host code and the libraries are Lamp's own files, the build needs
/// a toolchain Lamp downloads with Microsoft's licence accepted, and the agent plays the game in a preview on the Mac
/// (the same code drawn with Metal, out of sight, from a script of the controller's moves: `play`), which only code
/// can build and run. What reaches the device stays the integration's: finding it, setting it up, the install, the
/// launch, the picture and the log.
///
/// The game's folder: `Game/` (the agent's .cpp, .h and .glsl), `Assets/` (models, pictures, sounds the game reads with
/// `lamp_asset`), `Lamp/` (Lamp's, written before every turn and build, never the agent's), and `build/`.
enum GameKit {
    static let kind = "native-game"
    static let folder = "Lamp"

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Whether the app is a native game.
    static func isGame(_ project: LampProject) -> Bool {
        project.platform == .device && DeviceApps.appKind(for: project)?.lamp == kind
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

    /// Names every file of the kit's by its contents, so the build compiles Lamp's code again only when it changed.
    private static let stamp: String = {
        var hasher = SHA256()
        for file in files { hasher.update(data: Data(file.name.utf8)); hasher.update(data: file.data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined() + "\n"
    }()

    /// Every path Lamp owns in a game, as written in its folder.
    static var paths: [String] { files.map { "\(folder)/\($0.name)" } + ["\(folder)/kit.stamp"] }

    /// Writes Lamp's files into the game where they differ from what's there (so their dates move only when the kit
    /// changed), and the stamp after them.
    static func write(for project: LampProject) throws {
        guard !files.isEmpty else { throw Failure(message: "This copy of Lamp is missing its game kit.") }
        for file in files {
            try Template.put(file.data, at: project.dir.appendingPathComponent("\(folder)/\(file.name)"), for: project)
        }
        try Template.put(stamp, at: project.dir.appendingPathComponent("\(folder)/kit.stamp"), for: project)
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
        try Template.write(".lamp/\nbuild/\n", to: ".gitignore", for: project)
        try Template.write(appMd, to: "APP.md", for: project)
        try write(for: project)
    }

    static let appMd = """
    # {{NAME}}

    A 3D game for the Xbox, built and changed with Lamp: C++ in Game/ against Lamp's game kit (Lamp/lamp_game.h), with
    its models, pictures and sounds in Assets/. Lamp plays it in a preview on the Mac and puts it on the person's own Xbox.

    ## What it does
    Nothing yet: fresh scaffold, a ball the left stick rolls on a lit floor.

    """

    // MARK: Building

    enum Target: String { case xbox, preview }

    /// Runs the kit's build in the app's sandbox, with the tools where Lamp keeps them. The console's build leaves
    /// build/xbox.zip (App.exe and Assets/) for `DeviceApps` to package; the preview's, build/preview/lamp_preview.
    static func build(_ project: LampProject, for target: Target, started: (@MainActor (Process) -> Void)? = nil) async throws {
        if let problem = WindowsTools.problem { throw Failure(message: problem) }
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
    /// The rules for a native Xbox game, in the shape of a device app's.
    static func gamePrompt(for project: LampProject) -> String {
        let rules = [Rules.gameEdit, Rules.ask, Rules.shell, Rules.gameKit, Rules.gameSound, Rules.gameBudget, Rules.icon, Rules.about,
                     Rules.gameAssets, Rules.gameTry, Rules.appMd, Rules.audience, Rules.begin, Rules.finish]
        return (Rules.gameHeader + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: "Xbox")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "an Xbox")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "puts it on the Xbox again and opens it")
    }
}

extension Agent.Rules {
    static let gameHeader = """
    You are Lamp's builder agent. The current directory is a 3D game for the person's own Xbox, in Developer Mode, \
    which Lamp reaches over their network: C++ written against Lamp's game kit, which Lamp compiles on this Mac into \
    an Xbox app, packages and puts on the console. You play it in a preview on this Mac, the same code drawn with \
    Metal; the person plays it on their TV with the controller. Read APP.md first for context.
    """

    static let gameEdit = """
    - Make the change the user asks for by editing the game's files: its C++ (.cpp and .h) and shaders (.glsl) in \
    Game/, and what it loads in Assets/. Every .cpp and .glsl in Game/ is built. Lamp/ is Lamp's (the kit, written \
    before every build): read it, never edit or delete it. Lamp builds by itself when you look and puts the game on \
    the Xbox at the end of your turn, so don't run the build or reach the console yourself, and leave .lamp/ alone.
    """

    static let gameKit = """
    - Writing the game: read Lamp/lamp_game.h first, all of it; it's the whole interface. The game is \
    `game_init(const LampSetup*)` and `game_frame(const LampFrame*)`, which draws one frame (sg_begin_pass with \
    `frame->swapchain`, then sg_end_pass and sg_commit) and is called 60 times a second at 1920x1080. Lamp's host \
    makes the device and presents each frame with vsync: never present, sleep, wait or loop for time yourself, and \
    move things by `frame->dt`. Draw with sokol_gfx (Lamp/sokol_gfx.h, D3D11 on the console, Metal in the preview); \
    shapes from sokol_shape.h (boxes, spheres, cylinders, tori, planes), text with sokol_debugtext.h (on a canvas a \
    third of the screen, so letters are 24 px), lines and quick 2D with sokol_gl.h, maths with HandmadeMath.h \
    (right-handed, `HMM_Perspective_RH_ZO`), glTF models with cgltf.h (.glb, read through `lamp_asset` and \
    `cgltf_parse` with the data) and pictures with stb_image.h (`stbi_load_from_memory`). The implementations are \
    compiled in Lamp/lamp_kit.cpp, so include the headers without their IMPLEMENTATION defines. Shaders: one \
    annotated GLSL file per program in Game/ (see Game/scene.glsl and sokol-shdc's @vs/@fs/@program blocks, \
    uniform blocks of vec4 and mat4 only), which Lamp compiles to HLSL and Metal into `<name>.glsl.h` for you to \
    include; the console compiles the HLSL as the game starts. The controller is `frame->pads[0]`: sticks -1 to 1 \
    with up positive and the dead zone already out, triggers 0 to 1, buttons as LAMP_A… bits in `down`, `pressed` \
    and `released`; B is the game's (it doesn't leave the game), so use it for back or cancel, and Menu for pause. \
    Nothing outside the kit: no Windows or Apple headers, no threads, no files but `lamp_asset`, `lamp_save` and \
    `lamp_load`, no network, no rand() or time (use `lamp_random`, so the preview replays the same). Plain C++20 and \
    its standard library are fine.
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
    aloud, so the person hears it only on the Xbox; each look says what was played and how loud the mix came out: \
    keep its loudest under -3 dB, and play quieter what pushed it over full volume.
    """

    static let gameBudget = """
    - Keep within an Xbox One's means, the slowest console the game may run on, which gives a game in Developer Mode \
    only part of its GPU: under about 300 draws and 500,000 vertices a frame (the preview's stats count both), one \
    pass with one directional light computed in the shader, no shadow maps, post-processing or full-screen effects \
    beyond a sky gradient, textures at most 1024 px (keep each model's few), and many copies of one mesh drawn as one \
    instanced draw. Make meshes once in game_init, never per frame; allocate nothing per frame. The log says every \
    ten seconds how the console kept to 60 frames a second ("frames … ms on average, slowest … ms"): when frames \
    are late, draw less.
    """

    static let gameAssets = """
    - Files the user attaches are saved in Attachments/, for you to look at; they stay on this Mac. A model, picture \
    or data file the game uses is copied into Assets/, which goes into the package, and read with \
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
    isn't done. The preview is this Mac drawing, not the Xbox: it can't show speed, so keep to the budget above. \
    `look_at_app` with `on_device` builds the game for the console, puts it on the person's Xbox and opens it there, \
    and shows the Xbox's own picture of its screen and the game's log from the console; do that once the game plays \
    right in the preview, to see it start there and to read its frame times. Lamp can't press the Xbox's \
    controller: only the person can play it there.
    """
}
