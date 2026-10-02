import Foundation

/// The scaffold every generated app starts from.
enum Template {
    static func scaffold(name rawName: String, untitled: Bool = false, in root: URL) throws -> ForgeProject {
        let name = rawName.trimmed.filter { !"\"\\<>&/:".contains($0) }
        let exe = identifier(from: name)
        var slug = exe.lowercased()
        var n = 2
        while FileManager.default.fileExists(atPath: root.appendingPathComponent(slug).path) {
            slug = "\(exe.lowercased())-\(n)"
            n += 1
        }
        let project = ForgeProject(id: slug, name: name.isEmpty ? exe : name, exe: exe,
                                   dir: root.appendingPathComponent(slug), untitled: untitled)

        let files: [String: String] = [
            "Package.swift": packageSwift,
            "Sources/App.swift": appSwift,
            "Sources/ContentView.swift": contentViewSwift,
            "build.sh": buildSh,
            "APP.md": appMd,
            ".gitignore": ".build/\nbuild/\n.forge/\n",
        ]
        for (path, template) in files {
            let url = project.dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let contents = template
                .replacingOccurrences(of: "{{NAME}}", with: project.name)
                .replacingOccurrences(of: "{{EXE}}", with: project.exe)
                .replacingOccurrences(of: "{{SLUG}}", with: project.id)
                .replacingOccurrences(of: "{{BUNDLE}}", with: project.bundleID)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: project.dir.appendingPathComponent("build.sh").path)

        let forgeDir = project.dir.appendingPathComponent(".forge")
        try FileManager.default.createDirectory(at: forgeDir, withIntermediateDirectories: true)
        try JSONEncoder().encode(ProjectMeta(name: project.name, exe: project.exe, untitled: untitled ? true : nil))
            .write(to: forgeDir.appendingPathComponent("meta.json"))
        try writeSupport(for: project)
        return project
    }

    /// Per-app secret the app sends to Forge's AI gateway. Created on first use.
    static func token(for project: ForgeProject) -> String {
        let url = project.dir.appendingPathComponent(".forge/token")
        if let token = (try? String(contentsOf: url, encoding: .utf8))?.trimmed, !token.isEmpty { return token }
        let token = UUID().uuidString + UUID().uuidString
        try? token.write(to: url, atomically: true, encoding: .utf8)
        return token
    }

    /// Forge owns ForgeSupport.swift and rewrites it before every agent turn and build,
    /// so existing apps pick up helper improvements automatically.
    static func writeSupport(for project: ForgeProject) throws {
        let contents = forgeSupportSwift
            .replacingOccurrences(of: "{{SLUG}}", with: project.id)
            .replacingOccurrences(of: "{{TOKEN}}", with: token(for: project))
            .replacingOccurrences(of: "{{PORT}}", with: String(Gateway.port))
        // Left alone when it's already current, so its date only moves when the app needs a rebuild.
        let url = project.dir.appendingPathComponent("Sources/ForgeSupport.swift")
        if (try? String(contentsOf: url, encoding: .utf8)) != contents {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// "pomodoro timer!" → "PomodoroTimer"
    static func identifier(from name: String) -> String {
        let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var id = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        if id.isEmpty { id = "Untitled" }
        if id.first!.isNumber { id = "App" + id }
        return id
    }

    static let packageSwift = """
    // swift-tools-version:5.9
    import PackageDescription

    let package = Package(
        name: "{{EXE}}",
        platforms: [.macOS(.v14)],
        targets: [.executableTarget(name: "{{EXE}}", path: "Sources")]
    )

    """

    static let appSwift = """
    import SwiftUI

    @main
    struct MainApp: SwiftUI.App {
        var body: some SwiftUI.Scene {
            WindowGroup("{{NAME}}") {
                ContentView()
            }
            .commands { ForgeCommands() }
        }
    }

    """

    static let contentViewSwift = """
    import SwiftUI

    struct ContentView: View {
        var body: some View {
            VStack(spacing: 12) {
                Image(systemName: "hammer")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("{{NAME}}")
                    .font(.title2.bold())
                Text("Press ⇧⌘E to tell Forge what to build.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 420, minHeight: 300)
        }
    }

    """

    static let forgeSupportSwift = #"""
    // Generated by Forge before every build. Don't edit: changes are overwritten.
    import SwiftUI
    import AppKit

    /// Adds "Edit with Forge…" (⇧⌘E), which jumps back to this app's chat in Forge.
    struct ForgeCommands: Commands {
        init() {
            ForgeRuntime.start
            ForgeWindows.start
        }

        var body: some Commands {
            CommandGroup(after: .appInfo) {
                Button("Edit with Forge…") {
                    NSWorkspace.shared.open(URL(string: "forge://edit?app={{SLUG}}")!)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }

    /// Lets Forge's Play button bring this app back with a window: macOS's "reopen" request doesn't make a
    /// SwiftUI app open one when another app asks, so Forge sends this message instead.
    enum ForgeWindows {
        static let start: Void = {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("dev.forge.showWindow"), object: Bundle.main.bundleIdentifier, queue: .main
            ) { _ in
                MainActor.assumeIsolated { show() }
            }
        }()

        @MainActor static func show() {
            NSApp.unhide(nil)
            let windows = NSApp.windows.filter { $0.canBecomeMain }
            if let minimized = windows.first(where: \.isMiniaturized), !windows.contains(where: \.isVisible) {
                minimized.deminiaturize(nil)
            } else if !windows.contains(where: \.isVisible), let item = newWindowItem(in: NSApp.mainMenu),
                      let menu = item.menu {
                // SwiftUI's File ▸ New … Window (⌘N).
                menu.performActionForItem(at: menu.index(of: item))
            }
            NSApp.activate()
            NSApp.windows.first { $0.isVisible && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }

        private static func newWindowItem(in menu: NSMenu?) -> NSMenuItem? {
            for item in menu?.items ?? [] {
                if item.keyEquivalent == "n", item.keyEquivalentModifierMask == .command, item.isEnabled { return item }
                if let found = newWindowItem(in: item.submenu) { return found }
            }
            return nil
        }
    }

    /// Saves what this app prints (`print`, `NSLog`, SwiftUI runtime warnings, fatal errors) and a picture of
    /// its windows to its Forge project, where Forge's builder looks to see what happened while the app ran.
    enum ForgeRuntime {
        static let folder = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Forge/Apps/{{SLUG}}/.forge/runtime")

        /// Runs once, at launch. Each launch starts a new log.txt and keeps the one before as previous-log.txt.
        static let start: Void = {
            let fm = FileManager.default
            // Only on a Mac where Forge has this app's project.
            guard fm.fileExists(atPath: folder.deletingLastPathComponent().path) else { return }
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            // Pictures: once the first window has settled, and whenever the user leaves the app
            // (often to ask Forge for a change).
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { snapshot() } }
            NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                   object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { snapshot() }
            }
            // Forge asks for fresh pictures when its builder wants to look at the app.
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("dev.forge.snapshot.{{SLUG}}"), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { snapshot() }
            }
            let log = folder.appendingPathComponent("log.txt")
            let previous = folder.appendingPathComponent("previous-log.txt")
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: log, to: previous)
            guard freopen(log.path, "a", stderr) != nil else { return }
            dup2(fileno(stderr), STDOUT_FILENO)
            setvbuf(stdout, nil, _IOLBF, 0)   // so nothing is lost if the app crashes
            setvbuf(stderr, nil, _IONBF, 0)
            fputs("Launched \(Date().formatted(date: .abbreviated, time: .standard))\n", stderr)
            NSSetUncaughtExceptionHandler { exception in
                fputs("Uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")\n"
                      + exception.callStackSymbols.prefix(20).joined(separator: "\n") + "\n", stderr)
            }
            trimmer.resume()
        }()

        /// Saves up to three open windows, frontmost first, as screenshot.png, screenshot-2.png and screenshot-3.png.
        /// The app draws its own windows, so this needs no screen recording permission.
        @MainActor
        static func snapshot() {
            let windows = NSApp.orderedWindows.filter {
                $0.isVisible && !$0.isMiniaturized && $0.frame.width > 40 && $0.frame.height > 40
            }
            guard !windows.isEmpty else { return }   // nothing on screen: keep the last pictures
            for index in 0..<3 {
                let url = folder.appendingPathComponent(index == 0 ? "screenshot.png" : "screenshot-\(index + 1).png")
                if index < windows.count, let png = picture(of: windows[index]) {
                    try? png.write(to: url, options: .atomic)
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }

        /// The window with its title bar, at most 1600 pixels on the long side.
        @MainActor
        private static func picture(of window: NSWindow) -> Data? {
            guard let view = window.contentView?.superview ?? window.contentView else { return nil }
            let size = view.bounds.size
            let scale = min(window.backingScaleFactor, 1600 / max(size.width, size.height))
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
            bitmap.size = size
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap.representation(using: .png, properties: [:])
        }

        /// Keeps a chatty app from filling the disk: past 1 MB, the log starts over.
        private static let trimmer: DispatchSourceTimer = {
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + 30, repeating: 30)
            timer.setEventHandler {
                var info = stat()
                guard fstat(fileno(stderr), &info) == 0, info.st_size > 1_000_000 else { return }
                ftruncate(fileno(stderr), 0)
                fputs("(Earlier output was dropped: the log passed 1 MB.)\n", stderr)
            }
            return timer
        }()
    }

    /// Files attached in Forge's chat, bundled inside this app (Contents/Resources/Attachments).
    ///
    ///     let logo = ForgeAssets.image("logo.png")
    ///     let csv = ForgeAssets.text("prices.csv")
    enum ForgeAssets {
        static var folder: URL? { Bundle.main.resourceURL?.appendingPathComponent("Attachments") }

        static func url(_ name: String) -> URL? {
            guard let url = folder?.appendingPathComponent(name),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }

        static func image(_ name: String) -> NSImage? { url(name).flatMap(NSImage.init(contentsOf:)) }

        static func text(_ name: String) -> String? { url(name).flatMap { try? String(contentsOf: $0, encoding: .utf8) } }

        /// Every attached file's name.
        static var names: [String] {
            guard let folder else { return [] }
            return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        }
    }

    /// AI for this app, using the same AI account as Forge. No API keys needed.
    ///
    ///     let summary = try await ForgeAI.ask("Summarise these notes:\n\(notes)")
    ///
    ///     struct Items: Decodable { let items: [String] }
    ///     let result = try await ForgeAI.ask("Extract action items from:\n\(notes)\n" +
    ///         #"Reply as JSON: {"items": ["..."]}"#, as: Items.self)
    ///
    /// Pass images (photos, screenshots, camera frames) to have the AI look at them:
    ///
    ///     let verdict = try await ForgeAI.ask("What's in this photo?", images: [photo])
    ///
    /// To read text, barcodes or faces, or to tag images, use Vision instead: it's on-device, instant and free.
    ///
    /// Create or edit pictures with an image model:
    ///
    ///     let poster = try await ForgeAI.makeImage("a retro travel poster of Lisbon", aspectRatio: "3:4")
    ///     let edited = try await ForgeAI.editImage(photo, "turn this into a watercolour painting")
    ///     let combined = try await ForgeAI.editImages([person, beach], "put the person from the first photo on this beach")
    ///
    /// Make quick decisions with a decision model (Jev): probabilities and confidence, not text.
    /// Use these to classify, route, filter, prioritise, match or moderate anything by its meaning.
    /// They're smart, answer in well under a second and cost about $0.04 per million input tokens, so judging
    /// every item (hundreds of files, messages or rows) is fine and costs a fraction of a cent. Prefer them to
    /// keyword lists or hand-written rules that guess at meaning; keep exact facts (sizes, dates) in code and
    /// pass them in as part of the state.
    ///
    ///     let urgent = try await ForgeAI.isTrue("Does this message need a reply today?", about: email)   // 0…1
    ///     let team = try await ForgeAI.choose("Which team should handle this?", from: ["billing", "bugs", "sales"], about: ticket)
    ///     if team.confidence ?? 0 > 0.7 { route(to: team.choice!) } else { askUser() }
    ///     let mood = try await ForgeAI.rate("How frustrated is the customer?", levels: ["Calm", "Annoyed", "Furious"], about: ticket)
    ///
    /// `about:` takes text, a dictionary/array, or any Encodable value. Ask several questions about the same
    /// thing in one request with `ForgeAI.decide(about:_:)`; they run in parallel. To judge many items, run one
    /// call per item concurrently:
    ///
    ///     let verdicts = try await withThrowingTaskGroup(of: (URL, Double).self) { group in
    ///         for file in files {
    ///             group.addTask {
    ///                 let info: [String: Any] = ["name": file.lastPathComponent, "size_mb": sizeMB(file), "days_old": age(file)]
    ///                 return (file, try await ForgeAI.isTrue("Is this file safe to throw away?", about: info))
    ///             }
    ///         }
    ///         return try await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
    ///     }
    ///
    /// Text calls take a few seconds; decisions well under a second; image calls 10–60 seconds. Show a ProgressView, and show
    /// `error.localizedDescription` on failure. Aspect ratios look like "1:1", "16:9", "3:4".
    enum ForgeAI {
        struct Failure: LocalizedError {
            let message: String
            var errorDescription: String? { message }
        }

        static func ask(_ prompt: String, images: [NSImage] = [], system: String? = nil) async throws -> String {
            try await call(prompt: prompt, images: images, system: system, json: false)
        }

        /// Asks for JSON and decodes it. Describe the exact JSON shape in the prompt.
        static func ask<T: Decodable>(_ prompt: String, images: [NSImage] = [], system: String? = nil,
                                      as type: T.Type) async throws -> T {
            let text = try await call(prompt: prompt, images: images, system: system, json: true)
            do {
                return try JSONDecoder().decode(T.self, from: Data(text.utf8))
            } catch {
                throw Failure(message: "The AI's answer wasn't in the expected format. Try again.")
            }
        }

        /// Creates a new picture from a description.
        static func makeImage(_ description: String, aspectRatio: String = "1:1") async throws -> NSImage {
            try await image(prompt: description, images: [], aspectRatio: aspectRatio)
        }

        /// Changes a picture following an instruction, e.g. "remove the background" or "make it night time".
        /// Leave `aspectRatio` nil to keep the original shape where the model allows.
        static func editImage(_ image: NSImage, _ instruction: String, aspectRatio: String? = nil) async throws -> NSImage {
            try await self.image(prompt: instruction, images: [image], aspectRatio: aspectRatio)
        }

        /// Combines or edits several pictures following an instruction that can refer to them in order.
        static func editImages(_ images: [NSImage], _ instruction: String, aspectRatio: String? = nil) async throws -> NSImage {
            try await image(prompt: instruction, images: images, aspectRatio: aspectRatio)
        }

        // MARK: Decisions

        /// The probability (0…1) that the answer to a yes/no question is yes.
        static func isTrue(_ question: String, about state: Any, yes: String? = nil, no: String? = nil) async throws -> Double {
            let answer = try await decide(about: state, ["q": .yesNo(question, yes: yes, no: no)])["q"]
            guard let probability = answer?.probability else { throw Failure(message: "The decision model didn't answer.") }
            return probability
        }

        /// Picks one option. Check `confidence` before acting on a close call; `probabilities` has every option.
        static func choose(_ question: String, from options: [String], about state: Any) async throws -> ForgeDecision {
            guard let answer = try await decide(about: state, ["q": .choice(question, options: options)])["q"] else {
                throw Failure(message: "The decision model didn't answer.")
            }
            return answer
        }

        /// Places something on a scale of described levels. `score` runs from 0 to levels.count - 1 and can
        /// land between levels.
        static func rate(_ question: String, levels: [String], about state: Any) async throws -> ForgeDecision {
            guard let answer = try await decide(about: state, ["q": .score(question, levels: levels)])["q"] else {
                throw Failure(message: "The decision model didn't answer.")
            }
            return answer
        }

        /// Asks several questions about the same thing in one request. Answers come back under the same keys.
        static func decide(about state: Any, _ questions: [String: ForgeQuestion]) async throws -> [String: ForgeDecision] {
            let reply = try await post("/ai/decide", [
                "state": try jsonState(state),
                "questions": questions.mapValues(\.json),
            ])
            let answers = reply["answers"] as? [String: [String: Any]] ?? [:]
            return answers.mapValues(ForgeDecision.init)
        }

        private static func jsonState(_ state: Any) throws -> Any {
            if let text = state as? String { return text }
            if JSONSerialization.isValidJSONObject(state) { return state }
            if let value = state as? any Encodable {
                return try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
            }
            throw Failure(message: "Pass text, a dictionary or array, or an Encodable value to a decision.")
        }

        private static func image(prompt: String, images: [NSImage], aspectRatio: String?) async throws -> NSImage {
            var body: [String: Any] = ["prompt": prompt, "images": images.compactMap(encode)]
            if let aspectRatio { body["aspect_ratio"] = aspectRatio }
            let reply = try await post("/ai/image", body)
            guard let base64 = reply["image"] as? String, let data = Data(base64Encoded: base64),
                  let picture = NSImage(data: data) else {
                throw Failure(message: "The image model didn't return a picture.")
            }
            return picture
        }

        private static func call(prompt: String, images: [NSImage], system: String?, json: Bool) async throws -> String {
            let reply = try await post("/ai", [
                "prompt": prompt, "system": system ?? "", "json": json, "images": images.compactMap(encode),
            ])
            guard let text = reply["text"] as? String else { throw Failure(message: "The AI request failed.") }
            return text
        }

        private static func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:{{PORT}}" + path)!)
            request.httpMethod = "POST"
            request.timeoutInterval = 240
            request.setValue("Bearer {{TOKEN}}", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            for attempt in 0..<2 {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                    if (response as? HTTPURLResponse)?.statusCode == 200 { return reply }
                    let message = reply["error"] as? String ?? "The AI request failed."
                    fputs("ForgeAI \(path) failed: \(message)\n", stderr)
                    throw Failure(message: message)
                } catch let error as URLError where error.code == .cannotConnectToHost && attempt == 0 {
                    // Forge isn't running: start it in the background, then retry once.
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = false
                    if let forge = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.forge.host") {
                        _ = try? await NSWorkspace.shared.openApplication(at: forge, configuration: config)
                    }
                    try await Task.sleep(for: .seconds(3))
                }
            }
            fputs("ForgeAI \(path) failed: couldn't reach Forge\n", stderr)
            throw Failure(message: "Couldn't reach Forge. Open Forge and try again.")
        }

        /// Downscales to at most 1568px on the long side (the most the model uses) and JPEG-encodes.
        private static func encode(_ image: NSImage) -> [String: String]? {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let scale = min(1, 1568 / Double(max(cg.width, cg.height)))
            let width = max(1, Int(Double(cg.width) * scale)), height = max(1, Int(Double(cg.height) * scale))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage(),
                  let jpeg = NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            else { return nil }
            return ["media_type": "image/jpeg", "data": jpeg.base64EncodedString()]
        }
    }

    /// A question for `ForgeAI.decide`. Put the full meaning in the question; give options/levels clear descriptions.
    struct ForgeQuestion {
        let json: [String: Any]

        /// Yes/no. Optionally describe what counts as yes and no.
        static func yesNo(_ question: String, yes: String? = nil, no: String? = nil) -> ForgeQuestion {
            var json: [String: Any] = ["type": "noul", "instructions": question]
            if yes != nil || no != nil { json["criteria"] = ["true": yes ?? "Yes", "false": no ?? "No"] }
            return ForgeQuestion(json: json)
        }

        /// Pick one of these options. Include a "none of these" option when nothing may fit.
        static func choice(_ question: String, options: [String]) -> ForgeQuestion {
            ForgeQuestion(json: ["type": "choice", "instructions": question,
                                 "criteria": Dictionary(uniqueKeysWithValues: options.map { ($0, NSNull()) })])
        }

        /// Pick one option, each with a description of when it applies.
        static func choice(_ question: String, options: [String: String]) -> ForgeQuestion {
            ForgeQuestion(json: ["type": "choice", "instructions": question, "criteria": options])
        }

        /// Rate on ordered levels (2–10), lowest first. Describe each level as a concrete situation.
        static func score(_ question: String, levels: [String]) -> ForgeQuestion {
            ForgeQuestion(json: ["type": "score", "instructions": question, "criteria": levels])
        }
    }

    /// The answer to one decision question.
    struct ForgeDecision {
        /// Yes/no questions: the probability (0…1) that the answer is yes.
        let probability: Double?
        /// Choice questions: the most likely option.
        let choice: String?
        /// Score questions: 0…levels-1, weighted by probability, so it can land between levels.
        let score: Double?
        /// Every option (choice) or level index as text (score), with its probability.
        let probabilities: [String: Double]
        /// Choice and score: how concentrated the probabilities are (0…1). Low means a close call.
        let confidence: Double?

        init(_ json: [String: Any]) {
            probability = json["noul"] as? Double
            choice = json["choice"] as? String
            score = json["score"] as? Double
            probabilities = json["probabilities"] as? [String: Double] ?? [:]
            confidence = json["confidence"] as? Double
        }
    }

    """#

    static let buildSh = """
    #!/bin/zsh
    # Builds build/{{EXE}}.app. Run after every change.
    set -euo pipefail
    cd "$(dirname "$0")"
    swift build -c debug 2>&1
    BIN="$(swift build -c debug --show-bin-path)/{{EXE}}"
    APP="build/{{EXE}}.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS"
    cp "$BIN" "$APP/Contents/MacOS/{{EXE}}"
    cat > "$APP/Contents/Info.plist" <<PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleExecutable</key><string>{{EXE}}</string>
      <key>CFBundleIdentifier</key><string>{{BUNDLE}}</string>
      <key>CFBundleName</key><string>{{NAME}}</string>
      <key>CFBundleDisplayName</key><string>{{NAME}}</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>0.1</string>
      <key>LSMinimumSystemVersion</key><string>14.0</string>
      <key>NSPrincipalClass</key><string>NSApplication</string>
      <key>NSHighResolutionCapable</key><true/>
    </dict></plist>
    PLIST
    codesign --force -s - "$APP" >/dev/null 2>&1
    echo "Built $APP"

    """

    static let appMd = """
    # {{NAME}}

    A macOS SwiftUI app built and live-edited with Forge.

    ## What it does
    Nothing yet: fresh scaffold.

    ## Structure
    - `Sources/App.swift`: entry point and window.
    - `Sources/ContentView.swift`: main UI.
    - `Sources/ForgeSupport.swift`: generated by Forge ("Edit with Forge" command and `ForgeAI`). Don't edit.
    - `build.sh`: builds `build/{{EXE}}.app`.

    """
}
