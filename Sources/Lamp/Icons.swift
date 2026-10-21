import AppKit
import CoreImage
import CryptoKit
import ImagePlayground
import SwiftUI
import Vision

/// The editable description of an app's icon, kept in `icon.json` in the app folder
/// (so it's versioned with the app and the agent can change it on request).
struct IconSpec: Codable, Equatable {
    var subject: String         // the one object the icon shows, e.g. "a yellow legal pad with a red pencil"
    var symbol: String          // SF Symbol shown until (or instead of) generated artwork
    var background: String      // a name from Icons.backgrounds
    var tint: String            // hex main color of the object; colors the symbol on light backgrounds
    /// A game's icon is a rich painting filling the tile, not glass (`Icons.gamePrompt`).
    var game = false

    init(subject: String, symbol: String, background: String, tint: String, game: Bool = false) {
        self.subject = subject
        self.symbol = symbol
        self.background = background
        self.tint = tint
        self.game = game
    }

    private enum Keys: String, CodingKey { case subject, symbol, background, tint, game, art_prompt, foreground }

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
        game = try c.decodeIfPresent(Bool.self, forKey: .game) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(subject, forKey: .subject)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(background, forKey: .background)
        try c.encode(tint, forKey: .tint)
        if game { try c.encode(game, forKey: .game) }
    }
}

/// Icons follow Apple's layered structure: a calm background fill plus one foreground object, in Liquid Glass
/// like Lamp's own. The AI only picks the object; Lamp owns the canvas, so every icon sits on the same grid with
/// the same margins and lighting. The object starts as an SF Symbol and is upgraded to generated artwork (best
/// of several candidates, cut out of its background), drawn flat in solid colors: the glass, its light and its
/// depth are the system's, and a picture with its own shading under glass looks painted twice. With Xcode 26
/// installed the layers become a real Icon Composer document compiled with actool, so macOS 26 renders it in
/// Liquid Glass with dark and tinted variants; without Xcode, Lamp draws the layers itself, glass imitated.
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

    /// The choices that can make pictures now: the cloud models with a key, the Mac's own once it's in. With
    /// none, Codex may still draw (`AppAI.imageRoute`), with no model to choose.
    @MainActor static var usableChoices: [(id: String, label: String)] {
        imageChoices.filter { $0.id == localArt ? ImageModels.ready : Provider.hasKey }
    }

    /// The image model for pictures inside apps (Settings → Apps → Image generation).
    static var artModel: String { choice("imageModel") }

    /// The image model for icon artwork (Settings → Building → Image generation): the builder's business,
    /// so it has its own choice; an app that makes pictures needn't pay for the model that draws icons best.
    /// Until it's chosen, icons keep using the apps' model, as they did when there was one choice.
    /// With Image Playground chosen instead, this is the model that draws if it stops being available.
    static var iconModel: String {
        get { [nil, byHand].contains(iconChoice) ? artModel : choice("iconModel") }
        set { iconChoice = newValue }
    }

    /// What's saved for icon artwork: a model's id, `byHand`, or nothing (never chosen, or set back to none).
    static var iconChoice: String? {
        get { UserDefaults.standard.string(forKey: "iconModel") }
        set { UserDefaults.standard.set(newValue, forKey: "iconModel") }
    }

    /// The choice that means the person draws each app's icon in Image Playground. It's for icons only:
    /// Apple's picture maker has no way in but its own sheet, so nothing can be drawn while they're away,
    /// which rules it out for pictures inside apps and makes it no route for `AppAI.resolve`.
    static let byHand = "playground"
    static let byHandLabel = "Image Playground (you pick each icon)"

    /// Whether icons are drawn by hand: chosen, and Image Playground is still on this Mac. Where it has
    /// gone (Apple Intelligence turned off), the choice is kept for its return and Lamp carries on as if
    /// it hadn't been made: it draws with a model if one can, and says Not Ready if none can. Only
    /// `AppAI.resolve` asks this (for `.icon`); everything else reads its answer.
    static func drawnByHand(choice: String?, available: Bool) -> Bool { available && choice == byHand }

    /// How the Image generation row shows what answers, once something does (`AppAI.resolve` says whether
    /// anything does; with nothing, the row is Not Ready).
    enum ArtMenu: Equatable {
        /// One thing draws and there's nothing else to choose: it's named (by its id).
        case named(String)
        /// A menu of `ids` with `selected` shown: models, then `byHand`, then `none` (an empty id: no
        /// choice saved) when by hand is the only thing there is, so it can still be undone.
        case menu(ids: [String], selected: String)
    }

    /// The id of "None" in the menu, and of whatever draws with no model to choose (Codex's own).
    static let noChoice = ""

    /// `models` are the ones that can draw now, `selection` the one in use, `drawer` what draws when no
    /// model can be chosen (Codex with its own). By hand is an entry where it's on offer, and the one
    /// shown when it's what answers.
    static func artMenu(models: [String], selection: String, drawer: String?, byHandAvailable: Bool,
                        byHandChosen: Bool) -> ArtMenu {
        let chosen = byHandAvailable && byHandChosen
        let drawing = models.isEmpty && drawer != nil ? [noChoice] : models
        guard byHandAvailable else {
            if models.count > 1 { return .menu(ids: models, selected: models.contains(selection) ? selection : models[0]) }
            return .named(models.first ?? noChoice)
        }
        // By hand is all there is, and what answers (or the row would be Not Ready).
        if drawing.isEmpty { return .menu(ids: [byHand, noChoice], selected: byHand) }
        return .menu(ids: drawing + [byHand],
                     selected: chosen ? byHand : drawing.contains(selection) ? selection : drawing[0])
    }

    /// The menu's entries in the groups a line separates: by hand is another kind of thing from the models,
    /// and None is the way out of it. The line is drawn between groups, never beside an entry: a line that
    /// shares an entry's place in the list is what the closed menu shows for it, in place of its name.
    static func menuGroups(_ ids: [String]) -> [[String]] {
        ids.reduce(into: []) { groups, id in
            if groups.isEmpty || id == byHand || id == noChoice { groups.append([id]) } else { groups[groups.count - 1].append(id) }
        }
    }

    /// What picking an entry of the Image generation menu does. The menu ends in "Configure providers…",
    /// as the Text generation one does: it's where a key or a download is added, whatever the menu holds.
    enum MenuPick: Equatable { case providers, clear, choose(String) }
    static let configureProviders = "configure-providers"
    static func menuPick(_ id: String, forIcons: Bool) -> MenuPick {
        if id == configureProviders { return .providers }
        // "None" is only in the icon artwork menu; an empty id elsewhere is Codex drawing with its own.
        return forIcons && id == noChoice ? .clear : .choose(id)
    }

    /// What names a design's artwork in the chat: the line that offers to draw it is for this design only.
    static func artKey(_ project: LampProject, spec: IconSpec) -> String { artURL(project, spec: spec).lastPathComponent }

    /// Whether a "Draw Icon…" line in the chat still has something to offer: icons are drawn by hand, the
    /// line is about the design the app has now, and that design has no artwork yet.
    static func awaitsDrawing(_ key: String, in project: LampProject, byHand: Bool) -> Bool {
        guard byHand, let spec = load(project) else { return false }
        return artKey(project, spec: spec) == key && artwork(project, spec: spec) == nil
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

        /// The one color the tile is filled with at every stage (the blueprint, the symbol, the glass): Icon
        /// Composer lights it with its own slight gradient, and Lamp's drawings do the same (`gradient`).
        var fill: String { name == "white" ? "#F2F2F5" : bottom }

        /// The fill as a slight gradient from top to bottom, the way Icon Composer's automatic one looks.
        var gradient: (top: NSColor, bottom: NSColor) { Icons.gradient(from: fill) }
    }

    static func gradient(from hex: String) -> (top: NSColor, bottom: NSColor) {
        let base = color(hex: hex) ?? .gray
        return (base.blended(withFraction: 0.12, of: .white) ?? base, base)
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
    /// There while the icon on the app is the blueprint waiting for its artwork, so a relaunch of Lamp picks it up again.
    static func waitingURL(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/icon-waiting") }
    /// The icon as iOS takes it: a plain 1024px square, which the device rounds itself.
    static func squareURL(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/AppIcon-square.png") }

    /// The icon at its largest size (1024px) as a PNG for Quick Look, named after the app so the panel's title reads well.
    /// It's drawn from the design as it is now, not copied from the .icns: while a turn has the app, new artwork is
    /// on show in the chat but reaches the .icns only when the turn ends. Each design gets a folder of its own, since
    /// Quick Look goes on showing what it once read at a path even after the file there changes.
    /// Falls back to the .icns, then the small sidebar preview, when there's no design to draw.
    static func largePreview(_ project: LampProject) async -> URL? {
        let fm = FileManager.default
        let folder = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Forge/Icons/\(project.id)", isDirectory: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys   // the same design must make the same key every time
        guard let spec = load(project), let encoded = try? encoder.encode(spec) else {
            let largest = NSImage(contentsOf: icnsURL(project))?.representations
                .compactMap { $0 as? NSBitmapImageRep }.max { $0.pixelsWide < $1.pixelsWide }
            if let png = largest?.representation(using: .png, properties: [:]),
               let url = write(png, named: project.name, key: png, in: folder) { return url }
            return fm.fileExists(atPath: previewURL(project).path) ? previewURL(project) : nil
        }
        // A picture the person chose is written over the artwork at the same path, so its date is part of the key.
        let dates = [artURL(project, spec: spec), glassURL(project, spec: spec)].map {
            (try? fm.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        }
        let key = encoded + Data("|\(dates[0])|\(dates[1])".utf8)
        if let url = cached(named: project.name, key: key, in: folder) { return url }
        let tile = await tile(spec, art: artwork(project, spec: spec))
        guard let png = onGrid(tile, size: 1024).representation(using: .png, properties: [:]) else { return nil }
        return write(png, named: project.name, key: key, in: folder)
    }

    private static func previewFolder(for key: Data, in folder: URL) -> URL {
        folder.appendingPathComponent(SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined().prefix(16).description,
                                      isDirectory: true)
    }

    private static func cached(named name: String, key: Data, in folder: URL) -> URL? {
        let url = previewFolder(for: key, in: folder).appendingPathComponent("\(name).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Writes the picture into the key's folder and clears the app's earlier ones.
    private static func write(_ png: Data, named name: String, key: Data, in folder: URL) -> URL? {
        let fm = FileManager.default
        let own = previewFolder(for: key, in: folder)
        for old in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where old != own {
            try? fm.removeItem(at: old)
        }
        let url = own.appendingPathComponent("\(name).png")
        try? fm.createDirectory(at: own, withIntermediateDirectories: true)
        return (try? png.write(to: url)) != nil ? url : nil
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

    /// What stands in front of an icon's background, beside the symbol it shows until there's any: a design Lamp
    /// drew in layers of glass (`GlassIcons`), or a picture (painted where no glass design can be drawn, or chosen
    /// in Image Playground), cut out.
    enum Artwork {
        case glass(GlassArt)
        case picture(NSImage)
        /// None yet, but it's being drawn: the icon is the blueprint in the design's colors until it comes, so the
        /// design's symbol never passes for the icon.
        case waiting

        var picture: NSImage? { if case .picture(let image) = self { image } else { nil } }
    }

    /// Artwork depends on the subject and the colors it was painted to sit on.
    static func artURL(_ project: LampProject, spec: IconSpec) -> URL {
        project.dir.appendingPathComponent(".lamp/art/\(artHash(spec)).png")
    }

    /// A glass design for the same subject and colors, kept beside where its picture would be.
    static func glassURL(_ project: LampProject, spec: IconSpec) -> URL {
        project.dir.appendingPathComponent(".lamp/art/\(artHash(spec)).json")
    }

    private static func artHash(_ spec: IconSpec) -> String {
        // The key artwork has always had, so a picture someone chose in Image Playground is still found; a game's is
        // apart, since a painting filling the tile and a design for glass don't stand in for each other.
        let key = "v2|\(spec.subject.trimmed)|\(background(named: spec.background).name)|\(spec.tint.trimmed.lowercased())"
            + (spec.game ? "|game" : "")
        return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    /// The artwork kept for this design: a glass design first, since it's what Lamp draws when it can; a picture
    /// chosen in Image Playground takes its place by removing it (`Store.useIconPicture`).
    static func artwork(_ project: LampProject, spec: IconSpec) -> Artwork? {
        if let glass = GlassArt.load(from: glassURL(project, spec: spec)) { return .glass(glass) }
        return NSImage(contentsOf: artURL(project, spec: spec)).map(Artwork.picture)
    }

    /// Keeps a glass design as the icon's artwork, in place of any picture for the same design.
    static func save(_ glass: GlassArt, for project: LampProject, spec: IconSpec) throws {
        let url = glassURL(project, spec: spec)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try glass.encoded().write(to: url, options: .atomic)
        try? FileManager.default.removeItem(at: artURL(project, spec: spec))
    }

    /// Asks the in-app AI model to design an icon from the app's name and APP.md, or, for a brand-new app,
    /// from the first thing its user asked for.
    /// `background`, when given, is the color already chosen with the app's name, which the blueprint has shown since:
    /// the icon keeps it, so the tile never changes color on the way to the icon.
    static func design(for project: LampProject, brief: String? = nil, avoiding current: IconSpec? = nil,
                       background chosen: String? = nil) async -> IconSpec {
        let about = brief.map { "Its user asked for: \($0)" }
            ?? AppFile.text(project.dir.appendingPathComponent("APP.md"), in: project) ?? ""
        let names = backgrounds.map(\.name).joined(separator: ", ")
        var prompt = """
        Design a macOS app icon for an app called "\(project.name)". About the app:
        \(about.prefix(3000))

        The icon shows ONE tangible, familiar object that stands for what the app does (a notebook, a camera, a \
        stopwatch, a stack of photos, a paint palette), in Apple's Liquid Glass style. Prefer a real-world metaphor \
        over a generic symbol.
        \(GlassIcons.styleGuide)

        The subject is ONE object, never two: not "a leaf overlapping a clipboard", not "a camera next to a photo". \
        The glass layers are that one object's own parts.

        Reply as JSON: {"subject": "<the object as a short noun phrase with one or two concrete details, \
        e.g. a yellow legal pad with a red pencil; name its parts and colors, never its texture or shading>", \
        "symbol": "<an SF Symbols name that really exists and is closest to the subject, e.g. note.text, camera.fill, timer>", \
        "background": "<one of: \(names)>", "tint": "#RRGGBB", "game": <true only when the app is a game>}
        Pick a background that suits the app's mood and lets the object stand out: like Apple's own, mostly one \
        vivid color with the object in white and that color's shades, sometimes white or graphite with a vivid \
        object. tint is the object's main color and must contrast with the background. A game's icon isn't glass: \
        it's painted rich and in 3D, so for a game the subject is its hero, its character or most recognizable \
        object, as the game would show it.
        """
        if let current, let json = try? String(data: JSONEncoder().encode(current), encoding: .utf8) {
            prompt += "\nMake it clearly different from the current icon (a different object and background): \(json)"
        }
        let chosen = chosen.map { background(named: $0).name }
        if let chosen { prompt += "\nThe background is already chosen: \(chosen). Use it, and pick tint to go with it." }
        var best: IconSpec?
        for _ in 0..<2 {
            guard let (text, _) = try? await AppAI.complete(prompt: prompt, images: [], system: "", json: true),
                  var spec = try? JSONDecoder().decode(IconSpec.self, from: Data(text.utf8)) else { break }
            spec.background = chosen ?? background(named: spec.background).name
            guard NSImage(systemSymbolName: spec.symbol, accessibilityDescription: nil) != nil, color(hex: spec.tint) != nil else {
                prompt += "\n\"\(spec.symbol)\" is not a valid SF Symbol name, or tint isn't a #RRGGBB color. Fix it."
                continue
            }
            // A second try for a subject that's two things; a sound one that still says so is better than none.
            guard let second = secondObject(in: spec.subject) else { return spec }
            best = spec
            prompt += "\n\"\(spec.subject)\" is two objects (\"\(second)\"). Make the subject one object."
        }
        if let best { return best }
        // The color already shown stays, even when nothing better than the stand-in design could be had.
        var standIn = fallback(for: project.name)
        if let chosen {
            standIn.background = chosen
            if background(named: chosen).isLight { standIn.tint = "#3A3A3C" }
        }
        return standIn
    }

    /// The words by which a subject puts a second object beside its one, if it does.
    static func secondObject(in subject: String) -> String? {
        let words = " " + subject.lowercased() + " "
        return [" overlapping ", " next to ", " beside ", " in front of ", " behind ", " on top of ", " alongside "]
            .first { words.contains($0) }?.trimmed
    }

    static func fallback(for name: String) -> IconSpec {
        let colored = backgrounds.filter { !$0.isLight }
        let index = abs(name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % colored.count
        return IconSpec(subject: "a glossy rounded cube", symbol: "cube.fill", background: colored[index].name, tint: "#FFFFFF")
    }

    // MARK: Rendering

    /// The foreground layers, bottom first: the object (artwork, or the SF Symbol) centered on transparent 1024px
    /// canvases, sized to Apple's grid so every icon has the same breathing room. Artwork is split into a layer for
    /// each of its colors (`pieces`), so each part is a piece of glass of its own, as in Lamp's icon.
    static func foregroundLayers(_ spec: IconSpec, art: NSImage?) -> [NSBitmapImageRep] {
        // A game's painting is the whole tile, cropped by its edges.
        if let art, spec.game {
            return [canvas(1024) { rect in
                let scale = max(1024 / max(1, art.size.width), 1024 / max(1, art.size.height))
                let drawn = NSSize(width: art.size.width * scale, height: art.size.height * scale)
                art.draw(in: NSRect(x: (1024 - drawn.width) / 2, y: (1024 - drawn.height) / 2, width: drawn.width, height: drawn.height))
            }]
        }
        if let art {
            // Each piece is drawn the size of the whole, so the pieces line up.
            return pieces(of: art).map { piece in canvas(1024) { rect in draw(piece, fittingSide: 1024 * 0.66, in: rect) } }
        }
        return [canvas(1024) { rect in
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
        }]
    }

    /// The full-bleed icon (rounded square, transparent corners) at 1024px, with whatever artwork it has.
    static func tile(_ spec: IconSpec, art: Artwork?) async -> NSImage {
        switch art {
        case .glass(let glass): return await GlassIcons.tile(glass)
        case .waiting:
            let (spec, blueprint) = await blueprint(for: spec)
            return await tile(spec, layers: foregroundLayers(spec, art: blueprint))
        default: return await tile(spec, layers: foregroundLayers(spec, art: art?.picture))
        }
    }

    /// The blueprint in the design's colors, as a picture filling the tile, and the design as one whose picture
    /// fills its tile: the blueprint is drawn flat, with no glass.
    @MainActor static func blueprint(for spec: IconSpec) -> (IconSpec, NSImage) {
        let bg = background(named: spec.background)
        let ground = BlueprintTile.ground(bg)
        let renderer = ImageRenderer(content: BlueprintTile(letter: nil, ground: ground).frame(width: 1024, height: 1024))
        renderer.scale = 1
        var flat = spec
        flat.game = true
        return (flat, renderer.nsImage ?? NSImage(size: NSSize(width: 1024, height: 1024)))
    }

    /// Lamp's own drawing of the icon, at once and without Icon Composer: for a drag.
    static func drawnTile(_ spec: IconSpec, art: Artwork?) -> NSBitmapImageRep {
        // The blueprint is drawn in SwiftUI, on the main thread: a drag while artwork is drawn gets the symbol.
        if case .glass(let glass) = art { return GlassIcons.drawn(glass) }
        return drawnTile(spec, layers: foregroundLayers(spec, art: art?.picture))
    }

    /// The full-bleed icon (rounded square, transparent corners) at 1024px.
    /// Uses Icon Composer's renderer when Xcode 26 is installed, so it matches what macOS 26 shows.
    static func tile(_ spec: IconSpec, layers: [NSBitmapImageRep]) async -> NSImage {
        if let tools = IconTools.found {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("forge-icon-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let doc = dir.appendingPathComponent("AppIcon.icon")
            let png = dir.appendingPathComponent("tile.png")
            if (try? writeDocument(spec, layers: layers, to: doc)) != nil,
               await tools.render(doc, size: 1024, to: png), let image = NSImage(contentsOf: png) {
                return image
            }
        }
        return NSImage(cgImage: drawnTile(spec, layers: layers).cgImage!, size: NSSize(width: 1024, height: 1024))
    }

    /// Lamp's own rendering of the layers, for Macs without Xcode 26: gradient fill, a soft top highlight,
    /// and the object with a gentle shadow beneath it, lit from above inside its own shape the way the glass
    /// would be, since the artwork is drawn flat for the glass.
    static func drawnTile(_ spec: IconSpec, layers: [NSBitmapImageRep]) -> NSBitmapImageRep {
        let bg = background(named: spec.background)
        let lights = layers.map { layer in
            canvas(1024) { rect in
                NSGradient(colors: [NSColor.white.withAlphaComponent(0.38), NSColor.white.withAlphaComponent(0), .clear],
                           atLocations: [0, 0.55, 1], colorSpace: .sRGB)?.draw(in: rect, angle: -90)
                layer.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1, respectFlipped: false, hints: nil)
            }
        }
        return canvas(1024) { rect in
            let shape = NSBezierPath(roundedRect: rect, xRadius: 1024 * 0.225, yRadius: 1024 * 0.225)
            shape.addClip()
            NSGradient(colors: [bg.gradient.top, bg.gradient.bottom])?.draw(in: rect, angle: -90)
            NSGradient(colors: [NSColor.white.withAlphaComponent(bg.isLight ? 0.5 : 0.22), .clear])?
                .draw(in: NSRect(x: 0, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)

            // A game's painting is lit already.
            for layer in layers where spec.game {
                layer.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            }
            for (index, layer) in layers.enumerated() where !spec.game {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(bg.isLight || index > 0 ? 0.18 : 0.3)
                shadow.shadowBlurRadius = index == 0 ? 28 : 14
                shadow.shadowOffset = NSSize(width: 0, height: index == 0 ? -14 : -6)
                shadow.set()
                layer.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
                lights[index].draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            }

            NSColor.white.withAlphaComponent(0.35).setStroke()
            let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 1024 * 0.225 - 2, yRadius: 1024 * 0.225 - 2)
            rim.lineWidth = 3
            rim.stroke()
        }
    }

    /// The same icon for iPhone and iPad, where the system rounds the corners and wants an opaque square: the
    /// tile's own gradient goes on behind it, so its transparent corners fill with the same colors, and the tile
    /// is drawn a little larger than the canvas so its rounded rim falls outside.
    static func square(_ spec: IconSpec, art: Artwork?, tile: NSImage) -> NSBitmapImageRep {
        let bg = background(named: spec.background)
        var colors = [bg.gradient.top, bg.gradient.bottom]
        if case .glass(let glass) = art {
            let ground = gradient(from: glass.design.background)
            colors = [ground.top, ground.bottom]
        }
        return canvas(1024) { rect in
            NSGradient(colors: colors)?.draw(in: rect, angle: -90)
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
    static func preview(_ spec: IconSpec, art: Artwork?) async -> NSImage {
        let tile = await tile(spec, art: art)
        let grid = onGrid(tile, size: 256)
        let image = NSImage(size: NSSize(width: 256, height: 256))
        image.addRepresentation(grid)
        return image
    }

    static func write(_ spec: IconSpec, art: Artwork?, for project: LampProject) async throws -> NSImage {
        let fm = FileManager.default
        try fm.createDirectory(at: project.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)

        // Every install asks for the icon, and drawing it (actool and Icon Composer's tool among it) takes seconds:
        // files already drawn from the same design, artwork, tools and Lamp are kept as they are.
        let key = renderKey(spec, art: art)
        let made = [icnsURL(project), squareURL(project), previewURL(project)] + (IconTools.found != nil ? [carURL(project)] : [])
        if let key, (try? String(contentsOf: renderKeyURL(project), encoding: .utf8)) == key,
           made.allSatisfy({ fm.fileExists(atPath: $0.path) }), let image = NSImage(contentsOf: previewURL(project)) {
            return image
        }
        try? fm.removeItem(at: renderKeyURL(project))

        try? fm.removeItem(at: carURL(project))
        try? fm.removeItem(at: documentURL(project))
        let tile: NSImage
        if case .glass(let glass) = art {
            if let tools = IconTools.found {
                try GlassIcons.writeDocument(glass.design, paintings: glass.paintings, to: documentURL(project))
                await tools.compile(documentURL(project), to: carURL(project))
            }
            tile = await GlassIcons.tile(glass)
        } else {
            var spec = spec, picture = art?.picture
            if case .waiting = art { (spec, picture) = await blueprint(for: spec) }
            let layers = foregroundLayers(spec, art: picture)
            if let tools = IconTools.found {
                try writeDocument(spec, layers: layers, to: documentURL(project))
                await tools.compile(documentURL(project), to: carURL(project))
            }
            tile = await self.tile(spec, layers: layers)
        }

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
        try square(spec, art: art, tile: tile).representation(using: .png, properties: [:])?.write(to: squareURL(project))

        if let preview { try preview.write(to: previewURL(project)) }
        if let key { try? key.write(to: renderKeyURL(project), atomically: true, encoding: .utf8) }
        return NSImage(contentsOf: previewURL(project)) ?? NSImage()
    }

    /// Where `write` notes what the icon's files were drawn from.
    static func renderKeyURL(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/icon-drawn") }

    /// What the icon's files are drawn from: the design, its artwork, Xcode's icon tools, and this Lamp, whose way of
    /// drawing may change. Nil when the artwork can't be read back, so the icon is drawn again.
    static func renderKey(_ spec: IconSpec, art: Artwork?) -> String? {
        var hasher = SHA256()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let design = try? encoder.encode(spec) else { return nil }
        hasher.update(data: design)
        switch art {
        case .glass(let glass):
            guard let data = try? glass.encoded() else { return nil }
            hasher.update(data: Data("glass".utf8)); hasher.update(data: data)
        case .picture(let picture):
            guard let data = picture.tiffRepresentation else { return nil }
            hasher.update(data: Data("picture".utf8)); hasher.update(data: data)
        case .waiting:
            hasher.update(data: Data("waiting".utf8))
        case nil:
            hasher.update(data: Data("none".utf8))
        }
        let lamp = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        hasher.update(data: Data("\(IconTools.found?.developer ?? "-")|\(lamp)|\(Bundle.main.executableURL.flatMap(Self.modified) ?? 0)".utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func modified(_ url: URL) -> Double? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970
    }

    /// An Icon Composer document: the background fill plus a group for each foreground layer, each in Liquid Glass
    /// as Lamp's own icon is (glass, specular highlights, a shadow in the layer's color, a little translucency, its
    /// own light). The artwork is drawn flat for it (`artPrompt`), so it takes the same glass a symbol does.
    static func writeDocument(_ spec: IconSpec, layers: [NSBitmapImageRep], to url: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try fm.createDirectory(at: url.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        var groups: [[String: Any]] = []
        for (index, layer) in layers.enumerated() {
            let name = index == 0 ? "foreground" : "foreground-\(index)"
            try layer.representation(using: .png, properties: [:])?
                .write(to: url.appendingPathComponent("Assets/\(name).png"))
            // Icon Composer lists the top group first. A game's painting has its own light and depth: no glass.
            groups.insert(spec.game ? [
                "layers": [["image-name": "\(name).png", "name": name, "glass": false]],
                "shadow": ["kind": "none", "opacity": 0.5],
                "translucency": ["enabled": false, "value": 0.5],
                "specular": false,
            ] : [
                "layers": [["image-name": "\(name).png", "name": name, "glass": true]],
                "shadow": ["kind": "layer-color", "opacity": 0.5],
                "translucency": ["enabled": true, "value": index == 0 ? 0.2 : 0.4],
                "specular": true,
                "lighting": "individual",
            ], at: 0)
        }
        let bg = background(named: spec.background)
        let document: [String: Any] = [
            "fill": ["automatic-gradient": composerColor(bg.fill)],
            "groups": groups,
            "supported-platforms": ["squares": ["macOS"]],
        ]
        try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            .write(to: url.appendingPathComponent("icon.json"))
    }

    /// Flat artwork split into a piece for each of its colors, bottom first, as Icon Composer takes up to four
    /// groups: the whole silhouette in its main color, then each other color on top of it, largest first. A pixel
    /// on the edge between two colors is put back as the color on top drawn partly over the one beneath, so the
    /// pieces drawn in order are the artwork again. Artwork that isn't flat (a picture chosen in Image Playground)
    /// is one piece.
    static func pieces(of art: NSImage) -> [NSImage] {
        guard let cg = art.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [art] }
        let scale = min(1, 1024 / CGFloat(max(cg.width, cg.height)))
        let w = max(1, Int(CGFloat(cg.width) * scale)), h = max(1, Int(CGFloat(cg.height) * scale))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data?.bindMemory(to: UInt8.self, capacity: w * h * 4) else { return [art] }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        typealias RGB = SIMD3<Double>
        func rgb(_ i: Int) -> RGB {
            let a = Double(data[i * 4 + 3]) / 255
            return RGB(Double(data[i * 4]), Double(data[i * 4 + 1]), Double(data[i * 4 + 2])) / 255 / a
        }
        func distance(_ a: RGB, _ b: RGB) -> Double { ((a - b) * (a - b)).sum() }
        // The colors of the solid inside, without the soft edge, a sample of them being enough to find the few there are.
        let solid = (0..<w * h).filter { data[$0 * 4 + 3] > 240 }
        guard solid.count > 500 else { return [art] }
        let sample = stride(from: 0, to: solid.count, by: max(1, solid.count / 20000)).map { rgb(solid[$0]) }

        // The fewest colors that describe it: k-means started from the colors farthest apart, the same every time.
        let mean = sample.reduce(RGB(), +) / Double(sample.count)
        func clusters(_ k: Int) -> (centers: [RGB], missed: Double) {
            func nearest(_ c: RGB, _ centers: [RGB]) -> Double { centers.map { distance(c, $0) }.min() ?? distance(c, mean) }
            var centers: [RGB] = []
            while centers.count < k { centers.append(sample.max { nearest($0, centers) < nearest($1, centers) }!) }
            var missed = 0.0
            for _ in 0..<12 {
                var sums = [RGB](repeating: RGB(), count: centers.count), counts = [Double](repeating: 0, count: centers.count)
                missed = 0
                for c in sample {
                    let (index, d) = centers.enumerated().map { ($0.offset, distance(c, $0.element)) }.min { $0.1 < $1.1 }!
                    sums[index] += c; counts[index] += 1
                    if d > 0.15 * 0.15 { missed += 1 }
                }
                centers = centers.indices.map { counts[$0] > 0 ? sums[$0] / counts[$0] : centers[$0] }
            }
            return (centers, missed / Double(sample.count))
        }
        // Enough colors that next to nothing is far from one: a small part (a pair of eyes) counts as much as a big
        // one, since it's what makes the object what it is.
        var found = clusters(1)
        for k in 2...4 where found.missed > 0.003 { found = clusters(k) }
        // A picture still far from its colors is shaded, not flat.
        guard found.centers.count > 1, found.missed < 0.05 else { return [art] }
        var share = [Double](repeating: 0, count: found.centers.count)
        for c in sample { share[found.centers.indices.min { distance(c, found.centers[$0]) < distance(c, found.centers[$1]) }!] += 1 }
        // A color hardly there at all is a speck the cut-out left, not a part.
        let kept = found.centers.indices.filter { share[$0] / Double(sample.count) >= 0.002 }.sorted { share[$0] > share[$1] }
        guard kept.count > 1 else { return [art] }
        let base = found.centers[kept[0]]
        let tops = kept.dropFirst().map { found.centers[$0] }

        var layers = [[UInt8]](repeating: [UInt8](repeating: 0, count: w * h * 4), count: tops.count + 1)
        func put(_ layer: Int, _ i: Int, _ color: RGB, _ alpha: Double) {
            for c in 0..<3 { layers[layer][i * 4 + c] = UInt8((min(1, max(0, color[c])) * alpha * 255).rounded()) }
            layers[layer][i * 4 + 3] = UInt8((alpha * 255).rounded())
        }
        for i in 0..<w * h {
            let a = Double(data[i * 4 + 3]) / 255
            guard a > 0 else { continue }
            put(0, i, base, a)
            let p = rgb(i)
            // How much of each color on top, laid over the base, makes this pixel: the one that makes it most nearly.
            var best: (layer: Int, t: Double, miss: Double)?
            for (index, top) in tops.enumerated() {
                let line = top - base
                let t = min(1, max(0, ((p - base) * line).sum() / max(1e-6, (line * line).sum())))
                let miss = distance(p, base + line * t)
                if best == nil || miss < best!.miss { best = (index + 1, t, miss) }
            }
            if let best, best.t > 0.02 { put(best.layer, i, tops[best.layer - 1], a * best.t) }
        }
        return layers.compactMap { pixels in
            var pixels = pixels
            return pixels.withUnsafeMutableBytes { bytes in
                CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            }.map { NSImage(cgImage: $0, size: art.size) }
        }
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
                    do {
                        let data = try await generateArt(spec)
                        // A game's painting fills the tile, background and all.
                        if spec.game, let painting = NSImage(data: data) { return .success(painting) }
                        return .success(defringe(try cutOut(data), background: backgroundColor(of: data)))
                    } catch { return .failure(error) }
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
        for art in candidates { tiles.append(await tile(spec, layers: foregroundLayers(spec, art: art))) }
        guard let sheet = contactSheet(tiles).representation(using: .png, properties: [:]) else { return candidates[0] }

        let prompt = """
        These are \(tiles.count) candidate macOS app icons for an app called "\(appName)", numbered 1 to \
        \(tiles.count) from left to right. Each is shown large, then at its real 32px size on light and on dark. \
        The icon is meant to show: \(spec.subject).
        Judge each against this guide, against clean edges with no leftover background, halo or cut-off parts, and \
        against how polished and native it looks next to Apple's own icons:
        \(spec.game ? gameGuide : GlassIcons.styleGuide)
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

    /// What makes a game's icon: the tile's shape like any other, and in it a painting as rich as the game itself.
    static let gameGuide = """
    Games' icons on the App Store (Angry Birds, Cut the Rope, Pac-Man, Monument Valley):
    - The rounded tile like every app's, filled edge to edge by one rich, vivid painting: no glass, no flat shapes.
    - One hero, the game's character or its most recognizable object, rendered in glossy 3D with real light, depth \
    and texture, big and close, often bursting forward or out of a frame drawn in the scene, and cropped by the \
    tile's edges so it feels larger than the icon.
    - A background that sets the mood: a saturated gradient, a burst of light or a simple scene from the game, never \
    busy enough to compete with the hero.
    - Bold, joyful color with strong contrast; it must still read at 32 pixels.
    - No text, letters, logos, borders, or a rounded tile drawn inside the picture.
    """

    /// What an image model is asked to paint for a game's icon: the whole square, which the tile's corners crop.
    static func gamePrompt(_ spec: IconSpec) -> String {
        let bg = background(named: spec.background)
        return """
        Square app icon artwork for a game: \(spec.subject), as the hero, rendered in glossy 3D like a premium \
        mobile game's icon, with rich light, depth and texture. The hero is big and close, bursting forward, partly \
        cropped by the edges of the square so it feels larger than the frame; its most important part stays in the \
        middle 70%. Behind it, a \(bg.name) background with a saturated gradient or a soft burst of light that sets \
        the mood without competing. Bold, joyful colors with strong contrast that still read when tiny. The \
        painting fills the square edge to edge. No text, no letters, no logo, no border, no frame around the square, \
        no rounded corners, no app icon shape drawn in it.
        """
    }

    /// What an image model is asked to draw for an icon: the object flat, as the shapes of an Icon Composer layer,
    /// since the glass adds the light, the depth and the highlights. It's drawn on a plain color it can be told
    /// apart from, so a white object for a colored icon isn't lost on light gray when it's cut out.
    static func artPrompt(_ spec: IconSpec) -> String {
        if spec.game { return gamePrompt(spec) }
        let bg = background(named: spec.background)
        let light = (color(hex: spec.tint)?.usingColorSpace(.sRGB)).map {
            0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent > 0.6
        } ?? false
        return """
        A single \(spec.subject), drawn as the artwork for a macOS 26 app icon in Apple's Liquid Glass style: one \
        tangible object with a bold, simple, instantly recognizable silhouette, made of a few large flat shapes, \
        like a clean vector illustration: one shape for its body and one or two smaller shapes laid on top of it \
        for its parts, as if cut from colored glass. Every shape is one solid color: no gradients, no shading, no highlights, \
        no reflections, no texture, no outlines and no fine detail, because the glass and its light are added \
        afterwards. Two or three colors at most, mainly \(spec.tint) and its lighter and darker shades, chosen to \
        stand out against a \(bg.name) background. Front view. The object alone, centered, filling about 70% of the frame, on a plain flat \
        \(light ? "dark charcoal gray" : "light gray") background. No scene, no ground, no shadow, no background \
        elements, no text, no letters, no border, no frame, no rounded square tile, no app icon shape.
        """
    }

    /// A picture for inside an app (`make_art`), asked for in the icon's words so the two look like a set: one
    /// object for Lamp to cut out, or a whole scene. The icon's tint keeps the colors in the same family.
    static func appArtPrompt(subject: String, tint: String?, scene: Bool) -> String {
        let colors = tint.map { "Calm, harmonious colors that go with \($0)." } ?? "Calm, harmonious colors."
        if scene {
            return """
            \(subject), as an illustration in the style of Apple's own app icons: smooth rounded forms, subtle soft \
            gradients, gentle light from above, simple shapes with little fine detail, clean and uncluttered. \(colors) \
            The picture fills the whole frame. No text, no letters, no border, no frame, no rounded square tile, no \
            app icon shape.
            """
        }
        return """
        A single \(subject), as an illustration in the style of Apple's own app icons: one tangible object with a \
        simple, instantly recognizable silhouette, smooth rounded forms, subtle soft gradients and gentle light \
        from above, front or slight three-quarter view. \(colors) The object alone, centered, filling about 80% of \
        the frame, on a plain flat light gray background. No scene, no ground, no cast shadow, no background \
        elements, no text, no letters, no border, no frame, no rounded square tile, no app icon shape.
        """
    }

    /// Paints a picture for inside an app with the icon's model: PNG data, and what it cost. A single object
    /// comes back cut out of its background.
    static func generateAppArt(subject: String, tint: String?, scene: Bool, aspect: String) async throws -> (Data, Double) {
        let (data, cost) = try await AppAI.image(prompt: appArtPrompt(subject: subject, tint: tint, scene: scene),
                                                 references: [], aspectRatio: scene ? aspect : "1:1", model: iconModel)
        // The picture is paid for by now, so a failure from here on carries what it cost.
        let image: NSImage?
        do {
            image = scene ? NSImage(data: data) : defringe(try cutOut(data), background: backgroundColor(of: data))
        } catch {
            throw AppAI.Failure(message: error.localizedDescription, cost: cost)
        }
        guard let tiff = image?.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw AppAI.Failure(message: "The image model returned an unreadable picture.", cost: cost)
        }
        return (png, cost)
    }

    /// The plain background a generated picture was drawn on, from its four corners.
    static func backgroundColor(of data: Data) -> (r: Double, g: Double, b: Double)? {
        guard let rep = NSBitmapImageRep(data: data), rep.pixelsWide > 16, rep.pixelsHigh > 16 else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var sum = (r: 0.0, g: 0.0, b: 0.0), n = 0.0
        for (cx, cy) in [(0, 0), (w - 8, 0), (0, h - 8), (w - 8, h - 8)] {
            for x in cx..<cx + 8 { for y in cy..<cy + 8 {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                sum.r += c.redComponent; sum.g += c.greenComponent; sum.b += c.blueComponent; n += 1
            } }
        }
        return n > 0 ? (sum.r / n, sum.g / n, sum.b / n) : nil
    }

    /// Vision's cut-out keeps the soft edge with the background's gray mixed into it, which shows as a light halo
    /// on a dark window. Takes the background back out of the edge pixels and pulls the edge in a little.
    static func defringe(_ image: NSImage, background: (r: Double, g: Double, b: Double)?) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.bindMemory(to: UInt8.self, capacity: cg.width * cg.height * 4) else { return image }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let g = background ?? (0.9, 0.9, 0.9)
        let bg = [g.r, g.g, g.b]
        let w = cg.width, h = cg.height
        let original = (0..<w * h).map { pixels[$0 * 4 + 3] }
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4
            let a = Double(original[y * w + x]) / 255
            guard a > 0 else { continue }
            // The outermost ring of the edge is mostly background whatever its color: each pixel takes the lowest
            // opacity around it, which pulls the edge in by a pixel, and soft edges are tightened a little more.
            var lowest = original[y * w + x]
            for ny in max(0, y - 1)...min(h - 1, y + 1) { for nx in max(0, x - 1)...min(w - 1, x + 1) {
                lowest = min(lowest, original[ny * w + nx])
            } }
            let out = max(0, min(1, (Double(lowest) / 255 - 0.1) / 0.9))
            guard a < 1 || out < 1 else { continue }
            // Stored premultiplied with the original opacity a: a·seen, where seen = a·object + (1 − a)·background.
            // The object's color is recovered with that a, then premultiplied by the new opacity.
            for c in 0..<3 {
                let seen = Double(pixels[i + c]) / 255 / a
                let object = a < 1 ? max(0, min(1, (seen - (1 - a) * bg[c]) / a)) : seen
                pixels[i + c] = UInt8((object * out * 255).rounded())
            }
            pixels[i + 3] = UInt8((out * 255).rounded())
        } }
        guard let cleaned = context.makeImage() else { return image }
        return NSImage(cgImage: cleaned, size: NSSize(width: cg.width, height: cg.height))
    }

    /// The same request as Image Playground takes it. Its sheet boils a long request down to a few words
    /// and loses the "no …" list on the way, turns down anything naming macOS or Apple ("Try describing
    /// something different"), and draws a whole rounded tile when asked for an "app icon". So it gets the
    /// object and the look in one short sentence. It has no use for a hex color: the subject names its own.
    static func playgroundPrompt(_ spec: IconSpec) -> String {
        let subject = spec.subject.trimmed
        return subject.prefix(1).uppercased() + subject.dropFirst() + """
        , a single object with a simple bold shape made of a few flat shapes of solid color, like glass pieces. \
        Centered on a plain flat light gray background, nothing else in the picture.
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
        if Pretend.isMissing("xcode") { return nil }
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
