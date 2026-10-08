import AppKit
import CoreImage
import CryptoKit
import ImagePlayground
import Vision

/// The editable description of an app's icon, kept in `icon.json` in the app folder
/// (so it's versioned with the app and the agent can change it on request).
struct IconSpec: Codable, Equatable {
    var subject: String         // the one object the icon shows, e.g. "a yellow legal pad with a red pencil"
    var symbol: String          // SF Symbol shown until (or instead of) generated artwork
    var background: String      // a name from Icons.backgrounds
    var tint: String            // hex main color of the object; colors the symbol on light backgrounds

    init(subject: String, symbol: String, background: String, tint: String) {
        self.subject = subject
        self.symbol = symbol
        self.background = background
        self.tint = tint
    }

    private enum Keys: String, CodingKey { case subject, symbol, background, tint, art_prompt, foreground }

    /// Also reads the older format (`art_prompt`, a two-color `background`, `foreground`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        symbol = try c.decode(String.self, forKey: .symbol)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
            ?? c.decodeIfPresent(String.self, forKey: .art_prompt) ?? "a simple emblem"
        tint = try c.decodeIfPresent(String.self, forKey: .tint)
            ?? c.decodeIfPresent(String.self, forKey: .foreground) ?? "#FFFFFF"
        if let name = try? c.decode(String.self, forKey: .background) {
            background = name
        } else {
            let colors = try c.decodeIfPresent([String].self, forKey: .background) ?? []
            background = Icons.nearestBackground(to: colors.last ?? "").name
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(subject, forKey: .subject)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(background, forKey: .background)
        try c.encode(tint, forKey: .tint)
    }
}

/// Icons follow Apple's layered structure: a calm background fill plus one foreground object.
/// The AI only picks the object; Lamp owns the canvas, so every icon sits on the same grid with
/// the same margins and lighting. The object starts as an SF Symbol and is upgraded to generated
/// artwork (best of several candidates, cut out of its background). With Xcode 26 installed the
/// layers become a real Icon Composer document compiled with actool, so macOS 26 renders it in
/// Liquid Glass with dark and tinted variants; without Xcode, Lamp draws the layers itself.
/// Generated artwork is cached under .lamp/art/, so undoing an icon change is instant and free.
enum Icons {
    static let artModels: [(id: String, label: String)] = [
        ("google/gemini-3.1-flash-image", "Nano Banana 2 (Gemini 3.1 Flash Image)"),
        ("google/gemini-nano-banana-2.1", "Nano Banana 2.1 (newest)"),
        ("google/gemini-3-pro-image", "Nano Banana Pro (Gemini 3 Pro Image, pricier)"),
        ("openai/gpt-image-2.5-sunburst", "GPT Image 2.5 Sunburst (OpenAI, pricier)"),
        ("openai/gpt-image-2.5-flare", "GPT Image 2.5 Flare (OpenAI, pricier)"),
        ("openai/gpt-image-2", "GPT Image 2 (OpenAI, pricier)"),
        ("google/gemini-3.1-flash-lite-image", "Nano Banana 2 Lite (fastest, cheapest)"),
    ]

    /// The id that means the picture model on this Mac, offered alongside the cloud models once one is installed.
    static let localArt = "local"

    /// What the pickers offer: the cloud models, and the Mac's own model when there is one.
    static var imageChoices: [(id: String, label: String)] {
        guard ImageModels.ready, let name = ImageModels.chosen?.name else { return artModels }
        return artModels + [(localArt, "\(name) on this Mac (free, private)")]
    }

    /// The image model for pictures inside apps (Settings → Apps → Image generation).
    static var artModel: String { choice("imageModel") }

    /// The image model for icon artwork (Settings → Building → Image generation): the builder's business,
    /// so it has its own choice; an app that makes pictures needn't pay for the model that draws icons best.
    /// Until it's chosen, icons keep using the apps' model, as they did when there was one choice.
    static var iconModel: String {
        get { UserDefaults.standard.string(forKey: "iconModel") == nil ? artModel : choice("iconModel") }
        set { UserDefaults.standard.set(newValue, forKey: "iconModel") }
    }

    private static func choice(_ key: String) -> String {
        let saved = UserDefaults.standard.string(forKey: key) ?? ""
        if saved == localArt, ImageModels.ready { return localArt }
        return artModels.contains { $0.id == saved } ? saved : artModels[0].id
    }

    /// Picks the best of the artwork candidates. A capable vision model; it sees one small contact sheet.
    static let judgeModel = "anthropic/claude-sonnet-5.5"
    static let candidateCount = 3

    // MARK: Backgrounds

    /// The only backgrounds an icon can use: soft top-to-bottom gradients in the spirit of Apple's own icons.
    struct Background {
        let name: String
        let top: String
        let bottom: String
        var isLight = false
    }

    static let backgrounds: [Background] = [
        Background(name: "white", top: "#FFFFFF", bottom: "#E3E3E8", isLight: true),
        Background(name: "graphite", top: "#5C5C63", bottom: "#1C1C1E"),
        Background(name: "blue", top: "#6CC5FF", bottom: "#0A6CFF"),
        Background(name: "indigo", top: "#9391F7", bottom: "#4A45D4"),
        Background(name: "purple", top: "#D29CFF", bottom: "#9038DB"),
        Background(name: "pink", top: "#FF94B4", bottom: "#EE3460"),
        Background(name: "red", top: "#FF8D7D", bottom: "#E0302A"),
        Background(name: "orange", top: "#FFC266", bottom: "#FF7A00"),
        Background(name: "yellow", top: "#FFE98A", bottom: "#FFC400", isLight: true),
        Background(name: "green", top: "#8DE391", bottom: "#28A745"),
        Background(name: "teal", top: "#72E1E8", bottom: "#0E9FB2"),
    ]

    static func background(named name: String) -> Background {
        backgrounds.first { $0.name == name.trimmed.lowercased() } ?? backgrounds[2]
    }

    static func nearestBackground(to hex: String) -> Background {
        guard let target = color(hex: hex)?.usingColorSpace(.sRGB) else { return backgrounds[2] }
        func distance(_ b: Background) -> CGFloat {
            guard let c = color(hex: b.bottom)?.usingColorSpace(.sRGB) else { return .infinity }
            return pow(c.redComponent - target.redComponent, 2) + pow(c.greenComponent - target.greenComponent, 2)
                + pow(c.blueComponent - target.blueComponent, 2)
        }
        return backgrounds.min { distance($0) < distance($1) }!
    }

    // MARK: Spec

    static func specURL(_ project: LampProject) -> URL { project.dir.appendingPathComponent("icon.json") }
    static func icnsURL(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/AppIcon.icns") }
    static func carURL(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/Assets.car") }
    static func documentURL(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/AppIcon.icon") }
    static func previewURL(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/icon.png") }
    /// The icon as iOS takes it: a plain 1024px square, which the device rounds itself.
    static func squareURL(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/AppIcon-square.png") }

    /// The icon at its largest size (1024px) as a PNG for Quick Look, named after the app so the panel's title reads well.
    /// Falls back to the small sidebar preview when there's no .icns yet.
    static func largePreview(_ project: LampProject) -> URL? {
        let fm = FileManager.default
        let folder = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Forge/Icons", isDirectory: true)
        let target = folder.appendingPathComponent("\(project.name).png")
        let largest = NSImage(contentsOf: icnsURL(project))?.representations
            .compactMap { $0 as? NSBitmapImageRep }.max { $0.pixelsWide < $1.pixelsWide }
        if let png = largest?.representation(using: .png, properties: [:]) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if (try? png.write(to: target)) != nil { return target }
        }
        return fm.fileExists(atPath: previewURL(project).path) ? previewURL(project) : nil
    }

    static func load(_ project: LampProject) -> IconSpec? {
        guard let data = try? Data(contentsOf: specURL(project)) else { return nil }
        return try? JSONDecoder().decode(IconSpec.self, from: data)
    }

    static func save(_ spec: IconSpec, for project: LampProject) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? encoder.encode(spec).write(to: specURL(project))
    }

    /// Artwork depends on the subject and the colors it was painted to sit on.
    static func artURL(_ project: LampProject, spec: IconSpec) -> URL {
        let key = "v2|\(spec.subject.trimmed)|\(background(named: spec.background).name)|\(spec.tint.trimmed.lowercased())"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)
        return project.dir.appendingPathComponent(".lamp/art/\(hash).png")
    }

    static func cachedArt(_ project: LampProject, spec: IconSpec) -> NSImage? {
        NSImage(contentsOf: artURL(project, spec: spec))
    }

    /// Asks the in-app AI model to design an icon from the app's name and APP.md, or, for a brand-new app,
    /// from the first thing its user asked for.
    static func design(for project: LampProject, brief: String? = nil, avoiding current: IconSpec? = nil) async -> IconSpec {
        let about = brief.map { "Its user asked for: \($0)" }
            ?? (try? String(contentsOf: project.dir.appendingPathComponent("APP.md"), encoding: .utf8)) ?? ""
        let names = backgrounds.map(\.name).joined(separator: ", ")
        var prompt = """
        Design a macOS app icon for an app called "\(project.name)". About the app:
        \(about.prefix(3000))

        Follow Apple's macOS app icon guidelines. The icon shows ONE tangible, familiar object that stands for \
        what the app does (a notebook, a camera, a stopwatch, a stack of photos, a paint palette). Not an abstract \
        shape, a letter, a UI screenshot, a person or a scene. Prefer a real-world metaphor over a generic symbol, \
        and avoid sparkles, stars, magic wands and brains for AI features.

        Reply as JSON: {"subject": "<the object as a short noun phrase with one or two concrete details, \
        e.g. a yellow legal pad with a red pencil>", \
        "symbol": "<an SF Symbols name that really exists and is closest to the subject, e.g. note.text, camera.fill, timer>", \
        "background": "<one of: \(names)>", "tint": "#RRGGBB"}
        Pick a background that suits the app's mood and lets the object stand out. Most great icons use white, \
        graphite or one saturated color. tint is the object's main color and must contrast with the background.
        """
        if let current, let json = try? String(data: JSONEncoder().encode(current), encoding: .utf8) {
            prompt += "\nMake it clearly different from the current icon (a different object and background): \(json)"
        }
        for _ in 0..<2 {
            guard let (text, _) = try? await AppAI.complete(prompt: prompt, images: [], system: "", json: true),
                  var spec = try? JSONDecoder().decode(IconSpec.self, from: Data(text.utf8)) else { break }
            spec.background = background(named: spec.background).name
            if NSImage(systemSymbolName: spec.symbol, accessibilityDescription: nil) != nil, color(hex: spec.tint) != nil {
                return spec
            }
            prompt += "\n\"\(spec.symbol)\" is not a valid SF Symbol name, or tint isn't a #RRGGBB color. Fix it."
        }
        return fallback(for: project.name)
    }

    static func fallback(for name: String) -> IconSpec {
        let colored = backgrounds.filter { !$0.isLight }
        let index = abs(name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % colored.count
        return IconSpec(subject: "a glossy rounded cube", symbol: "cube.fill", background: colored[index].name, tint: "#FFFFFF")
    }

    // MARK: Rendering

    /// The foreground layer: the object (artwork, or the SF Symbol) centered on a transparent 1024px canvas,
    /// sized to Apple's grid so every icon has the same breathing room.
    static func foregroundLayer(_ spec: IconSpec, art: NSImage?) -> NSBitmapImageRep {
        canvas(1024) { rect in
            if let art {
                draw(art, fittingSide: 1024 * 0.66, in: rect)
            } else {
                let bg = background(named: spec.background)
                let ink = bg.isLight ? (color(hex: spec.tint) ?? .systemBlue) : .white
                // Monochrome, so details such as a stopwatch's hand stay cut out rather than painted over.
                let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
                if let symbol = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    let tinted = NSImage(size: symbol.size, flipped: false) { r in
                        symbol.draw(in: r)
                        ink.set()
                        r.fill(using: .sourceAtop)
                        return true
                    }
                    draw(tinted, fittingSide: 1024 * 0.56, in: rect)
                }
            }
        }
    }

    /// The full-bleed icon (rounded square, transparent corners) at 1024px.
    /// Uses Icon Composer's renderer when Xcode 26 is installed, so it matches what macOS 26 shows.
    static func tile(_ spec: IconSpec, foreground: NSBitmapImageRep, artwork: Bool) async -> NSImage {
        if let tools = IconTools.found {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("forge-icon-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let doc = dir.appendingPathComponent("AppIcon.icon")
            let png = dir.appendingPathComponent("tile.png")
            if (try? writeDocument(spec, foreground: foreground, artwork: artwork, to: doc)) != nil,
               await tools.render(doc, size: 1024, to: png), let image = NSImage(contentsOf: png) {
                return image
            }
        }
        return NSImage(cgImage: drawnTile(spec, foreground: foreground).cgImage!, size: NSSize(width: 1024, height: 1024))
    }

    /// Lamp's own rendering of the layers, for Macs without Xcode 26: gradient fill, a soft top highlight,
    /// and the object with a gentle shadow beneath it.
    static func drawnTile(_ spec: IconSpec, foreground: NSBitmapImageRep) -> NSBitmapImageRep {
        let bg = background(named: spec.background)
        return canvas(1024) { rect in
            let shape = NSBezierPath(roundedRect: rect, xRadius: 1024 * 0.225, yRadius: 1024 * 0.225)
            shape.addClip()
            NSGradient(colors: [color(hex: bg.top) ?? .white, color(hex: bg.bottom) ?? .gray])?.draw(in: rect, angle: -90)
            NSGradient(colors: [NSColor.white.withAlphaComponent(bg.isLight ? 0.5 : 0.22), .clear])?
                .draw(in: NSRect(x: 0, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(bg.isLight ? 0.18 : 0.3)
            shadow.shadowBlurRadius = 28
            shadow.shadowOffset = NSSize(width: 0, height: -14)
            shadow.set()
            foreground.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            NSGraphicsContext.restoreGraphicsState()

            NSColor.white.withAlphaComponent(0.35).setStroke()
            let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 1024 * 0.225 - 2, yRadius: 1024 * 0.225 - 2)
            rim.lineWidth = 3
            rim.stroke()
        }
    }

    /// The same icon for iPhone and iPad, where the system rounds the corners and wants an opaque square: the
    /// tile's own gradient goes on behind it, so its transparent corners fill with the same colors, and the tile
    /// is drawn a little larger than the canvas so its rounded rim falls outside.
    static func square(_ spec: IconSpec, tile: NSImage) -> NSBitmapImageRep {
        let bg = background(named: spec.background)
        return canvas(1024) { rect in
            NSGradient(colors: [color(hex: bg.top) ?? .white, color(hex: bg.bottom) ?? .gray])?.draw(in: rect, angle: -90)
            tile.draw(in: rect.insetBy(dx: -8, dy: -8))
        }
    }

    /// Places a full-bleed tile on Apple's macOS grid: an 824pt square centered on a 1024pt canvas, with shadow.
    static func onGrid(_ tile: NSImage, size: Int) -> NSBitmapImageRep {
        canvas(size) { rect in
            let s = rect.width / 1024
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = 24 * s
            shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
            shadow.set()
            tile.draw(in: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Writes .lamp/AppIcon.icns, .lamp/icon.png and .lamp/AppIcon-square.png (for iPhone and iPad) and, with
    /// Xcode 26, .lamp/AppIcon.icon and .lamp/Assets.car (what macOS 26 uses for Liquid Glass). Returns the
    /// preview image.
    @discardableResult
    /// The icon as Lamp shows it, rendered in a temporary folder and nothing of the app's touched: for the
    /// chat while a build that will write the real files is still running.
    static func preview(_ spec: IconSpec, art: NSImage?) async -> NSImage {
        let tile = await tile(spec, foreground: foregroundLayer(spec, art: art), artwork: art != nil)
        let grid = onGrid(tile, size: 256)
        let image = NSImage(size: NSSize(width: 256, height: 256))
        image.addRepresentation(grid)
        return image
    }

    static func write(_ spec: IconSpec, art: NSImage?, for project: LampProject) async throws -> NSImage {
        let fm = FileManager.default
        try fm.createDirectory(at: project.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        let foreground = foregroundLayer(spec, art: art)

        try? fm.removeItem(at: carURL(project))
        try? fm.removeItem(at: documentURL(project))
        if let tools = IconTools.found {
            try writeDocument(spec, foreground: foreground, artwork: art != nil, to: documentURL(project))
            await tools.compile(documentURL(project), to: carURL(project))
        }
        let tile = await tile(spec, foreground: foreground, artwork: art != nil)

        let iconset = fm.temporaryDirectory.appendingPathComponent("forge-\(UUID().uuidString).iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }
        let sizes = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                     ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
        var preview: Data?
        for (name, pixels) in sizes {
            guard let png = onGrid(tile, size: pixels).representation(using: .png, properties: [:]) else { continue }
            try png.write(to: iconset.appendingPathComponent("icon_\(name).png"))
            if pixels == 256 { preview = png }
        }
        _ = await IconTools.run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", icnsURL(project).path])
        try square(spec, tile: tile).representation(using: .png, properties: [:])?.write(to: squareURL(project))

        if let preview { try preview.write(to: previewURL(project)) }
        return NSImage(contentsOf: previewURL(project)) ?? NSImage()
    }

    /// An Icon Composer document: the background fill plus one foreground group. A symbol gets the full
    /// Liquid Glass treatment; illustrated artwork keeps its own shading and only gets the system shadow.
    static func writeDocument(_ spec: IconSpec, foreground: NSBitmapImageRep, artwork: Bool, to url: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try fm.createDirectory(at: url.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        try foreground.representation(using: .png, properties: [:])?
            .write(to: url.appendingPathComponent("Assets/foreground.png"))
        let bg = background(named: spec.background)
        let document: [String: Any] = [
            "fill": ["linear-gradient": [composerColor(bg.top), composerColor(bg.bottom)]],
            "groups": [[
                "layers": [["image-name": "foreground.png", "name": "foreground", "glass": !artwork]],
                "shadow": ["kind": "neutral", "opacity": 0.5],
                "translucency": ["enabled": false, "value": 0.4],
            ]],
            "supported-platforms": ["squares": ["macOS"]],
        ]
        try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            .write(to: url.appendingPathComponent("icon.json"))
    }

    // MARK: Artwork

    /// Generates several artwork candidates in parallel, renders each as a finished icon and lets a vision
    /// model pick the one that best fits Apple's guidelines. Returns the winning object, cut out.
    static func generateBestArt(_ spec: IconSpec, appName: String,
                                log: @escaping @MainActor (String) -> Void) async throws -> NSImage {
        var candidates: [NSImage] = []
        var lastError: Error?
        await withTaskGroup(of: Result<NSImage, Error>.self) { group in
            for _ in 0..<candidateCount {
                group.addTask {
                    do { return .success(try cutOut(try await generateArt(spec))) } catch { return .failure(error) }
                }
            }
            for await result in group {
                switch result {
                case .success(let image): candidates.append(image)
                case .failure(let error): lastError = error
                }
            }
        }
        guard !candidates.isEmpty else { throw lastError ?? AppAI.Failure(message: "No artwork was generated.") }
        guard candidates.count > 1 else { return candidates[0] }

        var tiles: [NSImage] = []
        for art in candidates { tiles.append(await tile(spec, foreground: foregroundLayer(spec, art: art), artwork: true)) }
        guard let sheet = contactSheet(tiles).representation(using: .png, properties: [:]) else { return candidates[0] }

        let prompt = """
        These are \(tiles.count) candidate macOS app icons for an app called "\(appName)", numbered 1 to \
        \(tiles.count) from left to right. Each is shown large, then at its real 32px size on light and on dark. \
        The icon is meant to show: \(spec.subject).
        Judge each against Apple's Human Interface Guidelines for macOS app icons:
        - one clear, tangible object and nothing else: no scene, extra props, text, letters or second rounded tile
        - a simple, bold silhouette that still reads at 32px
        - clean edges with no leftover background, halo or cut-off parts
        - calm, harmonious color that stands out against the background
        - polished and native-looking next to Apple's own icons
        Reply as JSON: {"scores": [<1-10 for each icon, in order>], "best": <number of the best icon, from 1>, \
        "why": "<one short sentence>"}
        """
        struct Verdict: Decodable { let best: Int; let why: String? }
        let image = AppAI.Image(mediaType: "image/png", data: sheet.base64EncodedString())
        guard let (text, _) = try? await AppAI.complete(prompt: prompt, images: [image], system: "", json: true, model: judgeModel),
              let verdict = try? JSONDecoder().decode(Verdict.self, from: Data(text.utf8)),
              candidates.indices.contains(verdict.best - 1) else { return candidates[0] }
        if let why = verdict.why { await log("Picked icon artwork \(verdict.best) of \(candidates.count): \(why)") }
        return candidates[verdict.best - 1]
    }

    /// Asks the image model for the object alone on a plain background (never a whole icon), so Lamp can
    /// cut it out and compose the icon itself. Returns PNG/JPEG data.
    static func generateArt(_ spec: IconSpec) async throws -> Data {
        try await AppAI.image(prompt: artPrompt(spec), references: [], aspectRatio: "1:1", model: iconModel).0
    }

    /// What an image model is asked to draw for an icon.
    static func artPrompt(_ spec: IconSpec) -> String {
        let bg = background(named: spec.background)
        return """
        A single \(spec.subject), drawn as the object for a macOS app icon in Apple's own icon style: one tangible \
        object with a simple, instantly recognizable silhouette, smooth rounded forms, subtle soft gradients and \
        gentle light from above, front or slight three-quarter view. Two or three colors at most, mainly \
        \(spec.tint), chosen to stand out against a \(bg.name) background. The object alone, centered, filling about \
        70% of the frame, on a plain flat light gray background. No scene, no ground, no cast shadow, no \
        background elements, no text, no letters, no border, no frame, no rounded square tile, no app icon shape.
        """
    }

    /// The same request as Image Playground takes it. Its sheet boils a long request down to a few words
    /// and loses the "no …" list on the way, turns down anything naming macOS or Apple ("Try describing
    /// something different"), and draws a whole rounded tile when asked for an "app icon". So it gets the
    /// object and the look in one short sentence. It has no use for a hex color: the subject names its own.
    static func playgroundPrompt(_ spec: IconSpec) -> String {
        let subject = spec.subject.trimmed
        return subject.prefix(1).uppercased() + subject.dropFirst() + """
        , a single object with a simple bold shape, smooth rounded forms, soft gradients and gentle light \
        from above. Centered on a plain flat light gray background, nothing else in the picture.
        """
    }

    /// Whether this Mac can show Image Playground (Apple Intelligence on, a Mac that runs it). Apple's
    /// picture maker has no way in for an app but its own sheet, where the person picks the picture.
    static var playgroundAvailable: Bool {
        if #available(macOS 15.1, *) { return ImagePlaygroundViewController.isAvailable }
        return false
    }

    /// Lifts the object off its background with Vision's subject isolation (on-device, free).
    static func cutOut(_ data: Data) throws -> NSImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AppAI.Failure(message: "The image model returned an unreadable picture.")
        }
        let handler = VNImageRequestHandler(cgImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw AppAI.Failure(message: "Couldn't find an object in the generated artwork.")
        }
        let masked = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler,
                                                         croppedToInstancesExtent: true)
        let ci = CIImage(cvPixelBuffer: masked)
        guard let cut = CIContext().createCGImage(ci, from: ci.extent) else {
            throw AppAI.Failure(message: "Couldn't cut out the generated artwork.")
        }
        return NSImage(cgImage: cut, size: NSSize(width: cut.width, height: cut.height))
    }

    /// True for artwork made by `cutOut` (an object with transparent surroundings), rather than an opaque square.
    static func isCutOut(_ data: Data) -> Bool {
        guard let rep = NSBitmapImageRep(data: data), rep.hasAlpha, rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return false }
        let samples = (0..<24).flatMap { i in (0..<24).map { j in (i * (rep.pixelsWide - 1) / 23, j * (rep.pixelsHigh - 1) / 23) } }
        let clear = samples.filter { (rep.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? 1) < 0.1 }.count
        return clear * 20 >= samples.count   // at least 5% see-through
    }

    /// Candidates side by side: large on a light backdrop, then at real 32px size on light and dark.
    static func contactSheet(_ tiles: [NSImage]) -> NSBitmapImageRep {
        let column = 300, width = column * tiles.count
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 380, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor(white: 0.96, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: 380).fill()
        for (i, tile) in tiles.enumerated() {
            let x = CGFloat(i * column)
            NSString(string: "\(i + 1)").draw(at: NSPoint(x: x + 12, y: 350), withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.black,
            ])
            NSImage(cgImage: onGrid(tile, size: 256).cgImage!, size: NSSize(width: 256, height: 256))
                .draw(in: NSRect(x: x + 22, y: 84, width: 256, height: 256))
            NSColor(white: 0.12, alpha: 1).setFill()
            NSRect(x: x + 150, y: 10, width: 150, height: 64).fill()
            let small = NSImage(cgImage: onGrid(tile, size: 32).cgImage!, size: NSSize(width: 32, height: 32))
            small.draw(in: NSRect(x: x + 59, y: 26, width: 32, height: 32))
            small.draw(in: NSRect(x: x + 209, y: 26, width: 32, height: 32))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    // MARK: Helpers

    private static func canvas(_ size: Int, _ draw: (NSRect) -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Draws an image centered in `rect`, scaled so its longer side is `side`.
    private static func draw(_ image: NSImage, fittingSide side: CGFloat, in rect: NSRect) {
        let scale = min(side / image.size.width, side / image.size.height)
        let drawn = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: NSRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                              width: drawn.width, height: drawn.height))
    }

    /// Icon Composer's color notation, e.g. "srgb:0.00000,0.47843,1.00000,1.00000".
    private static func composerColor(_ hex: String) -> String {
        let c = color(hex: hex)?.usingColorSpace(.sRGB) ?? .white
        return "srgb:" + [c.redComponent, c.greenComponent, c.blueComponent, 1].map { String(format: "%.5f", $0) }
            .joined(separator: ",")
    }

    static func color(hex: String) -> NSColor? {
        var value = hex.trimmed
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = Int(value, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                       blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// Xcode 26's icon tools: `ictool` (Icon Composer's renderer) and `actool` (compiles .icon documents).
/// Lamp only needs the Command Line Tools, so these are optional: found in a full Xcode 26 install.
struct IconTools {
    let developer: String
    var ictool: String { developer + "/../Applications/Icon Composer.app/Contents/Executables/ictool" }
    var actool: String { developer + "/usr/bin/actool" }

    static let found: IconTools? = {
        let selected = try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")
        let candidates = [selected, "/Applications/Xcode.app/Contents/Developer", "/Applications/Xcode-beta.app/Contents/Developer"]
        return candidates.compactMap { $0 }.map(IconTools.init).first {
            FileManager.default.isExecutableFile(atPath: $0.ictool) && FileManager.default.isExecutableFile(atPath: $0.actool)
        }
    }()

    /// Renders the document as macOS 26 shows it (full bleed, transparent corners).
    func render(_ document: URL, size: Int, to png: URL) async -> Bool {
        await Self.run(ictool, [document.path, "--export-preview", "macOS", "Light", "\(size)", "\(size)", "1", png.path])
            && FileManager.default.fileExists(atPath: png.path)
    }

    /// Compiles the document into an Assets.car holding the `AppIcon` icon (Liquid Glass plus legacy sizes).
    @discardableResult
    func compile(_ document: URL, to car: URL) async -> Bool {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("forge-car-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        guard await Self.run(actool, [document.path, "--compile", out.path, "--platform", "macosx",
                                      "--minimum-deployment-target", "14.0", "--app-icon", "AppIcon",
                                      "--output-partial-info-plist", out.appendingPathComponent("partial.plist").path],
                             env: ["DEVELOPER_DIR": developer]) else { return false }
        try? FileManager.default.removeItem(at: car)
        return (try? FileManager.default.moveItem(at: out.appendingPathComponent("Assets.car"), to: car)) != nil
    }

    /// Runs a tool off the main thread, discarding its output. True when it exits cleanly.
    static func run(_ path: String, _ arguments: [String], env: [String: String] = [:]) async -> Bool {
        await Subprocess.run(path, arguments, env: env, timeout: 300).ok
    }
}
