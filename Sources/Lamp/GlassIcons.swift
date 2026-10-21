import AppKit
import CryptoKit

/// An icon built the way Apple builds its own in Liquid Glass: a few whole shapes stacked on a nearly solid
/// background, each made of a material Icon Composer renders (solid, clear or frosted glass, a lens that bends what's
/// behind it), with at most one painted layer of rich content under the glass. A model that draws in vectors writes the
/// shapes, looks at what Icon Composer made of them, and puts right what it sees; the finish is the system's own glass,
/// so the shapes are kept simple and the depth comes from how they overlap.
struct GlassDesign: Codable, Equatable {
    enum Material: String, Codable, CaseIterable {
        case solid, glass, frosted, lens, painted
    }

    struct Layer: Codable, Equatable {
        var name: String
        var material: Material
        /// The layer's shape on the whole tile, 1024 by 1024: whole even where a layer in front covers it.
        var svg: String
        /// Its color, lit by the system's gentle gradient; nil keeps the SVG's own fills (a soft glow drawn in).
        var color: String?
        var opacity: Double?
        /// For a painted layer: the picture, painted by an image model and cut to the layer's shape.
        var paint: String?
    }

    /// The tile's color, nearly solid: the system adds only its slight gradient.
    var background: String
    /// Back to front.
    var layers: [Layer]

    /// The same design in another hue, for a copy of the app: every color with any hue in it turns by as much as
    /// the background does, so its shades stay the background's. White, gray and black stay as they are, and so
    /// does a painting, whose layer's svg is only its shape.
    func recolored(to hex: String) -> GlassDesign {
        guard let from = Self.hsb(background), let to = Self.hsb(hex) else { return self }
        let turn = to.h - from.h
        func turned(_ text: String) -> String {
            guard let expression = try? NSRegularExpression(pattern: "#[0-9A-Fa-f]{6}\\b") else { return text }
            var result = text
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range, in: text) else { continue }
                result.replaceSubrange(range, with: Self.turn(String(text[range]), by: turn))
            }
            return result
        }
        var design = self
        design.background = hex
        design.layers = layers.map { layer in
            var layer = layer
            layer.color = layer.color.map(turned)
            if layer.material != .painted { layer.svg = turned(layer.svg) }
            return layer
        }
        return design
    }

    private static func hsb(_ hex: String) -> (h: CGFloat, s: CGFloat, b: CGFloat)? {
        guard let c = Icons.color(hex: hex)?.usingColorSpace(.sRGB) else { return nil }
        return (c.hueComponent, c.saturationComponent, c.brightnessComponent)
    }

    private static func turn(_ hex: String, by turn: CGFloat) -> String {
        guard let (h, s, b) = hsb(hex), s > 0.12 else { return hex }
        let c = NSColor(hue: (h + turn + 1).truncatingRemainder(dividingBy: 1), saturation: s, brightness: b, alpha: 1)
            .usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

/// A glass design with the picture its painted layer was painted with: what Lamp keeps as an icon's artwork
/// (`Icons.glassURL`) and what a shared file carries. Read only once it passes `GlassIcons.problem`, whoever wrote it.
struct GlassArt: Codable, Equatable {
    var design: GlassDesign
    var paintings: [String: Data]

    /// Larger than any design Lamp draws, with its painting.
    static let largest = 24 << 20

    static func load(from url: URL) -> GlassArt? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int), size <= largest,
              let data = try? Data(contentsOf: url) else { return nil }
        return decoded(data)
    }

    static func decoded(_ data: Data) -> GlassArt? {
        guard data.count <= largest, let art = try? JSONDecoder().decode(GlassArt.self, from: data),
              GlassIcons.problem(in: art.design) == nil else { return nil }
        // Only the painting for a painted layer, and only a picture the size Lamp makes.
        let wanted = Set(art.design.layers.filter { $0.material == .painted }.map(GlassIcons.paintingKey))
        let paintings = art.paintings.filter { wanted.contains($0.key) && GlassIcons.isPainting($0.value) }
        return GlassArt(design: art.design, paintings: paintings)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

enum GlassIcons {
    /// Draws the shapes and puts them right from a look: it needs to draw in vectors and see well.
    static let drawModel = "anthropic/claude-opus-5.5"
    static let candidateCount = 3
    /// How many times a candidate is looked at and drawn again. Timed with the candidates side by side: none is about
    /// 35 seconds and visibly rougher, one about a minute, two about 80 seconds and no better than one.
    static let rounds = 1

    /// What makes an icon look like Apple's own in Liquid Glass. The designer, the painter and the judge all read it.
    static let styleGuide = """
    Apple's macOS 26 icons in Liquid Glass (Podcasts, Launchpad, Preview, Photo Booth):
    - One bold, tangible object that stands for the app, filling about three quarters of the tile, simple enough to \
    read at 32 pixels: few, large details (a calendar needs no grid of days). Rounded ends and corners everywhere; no \
    thin lines. A diagonal pose suits things that move.
    - Built from two to four overlapping layers, each a whole shape of its own, stacked like cut pieces of glass or \
    acrylic: a fin tucked behind a rocket's body is drawn whole behind it, not as the part that shows.
    - At least one layer is translucent or frosted, and it overlaps a different shape, so you see that shape through it.
    - Tonal, vibrant color: the pieces are white or lighter and darker shades of the background's own hue, with one \
    vivid accent at most. Never a jumble of unrelated colors. White pieces on a colored tile are milky glass that the \
    color tints a little, like Launchpad's rocket, not flat white paper.
    - The background is one vivid color (or white, or graphite), almost solid: only a slight gradient.
    - Holes and cut-outs show what's behind them (a rocket's window shows the background), rather than painted circles.
    - Light comes from above. Each piece glows gently from within, a little lighter towards the top; shadows are soft \
    and short, falling from one layer onto the next, never heavy.
    - Glass can be the subject: one rich, vivid layer (a painted sky, an iridescent disc, a photo) under a thick glass \
    lens or a frosted panel that bends or blurs it.
    - No text or letters, no screenshots of an interface, no people, no scene, no sparkles, stars, wands or brains.
    """

    // MARK: Drawing

    /// Whether Lamp draws glass icons: the drawing model is reached with the OpenRouter key, and only when icons
    /// aren't to be painted by the model on this Mac, which someone chose to keep them free and private.
    static var canDraw: Bool { Provider.hasKey && Icons.iconModel != Icons.localArt }

    /// The best of a few designs, each drawn and then put right by looking at its rendering.
    static func generateBest(for spec: IconSpec, appName: String, about: String,
                             log: @escaping @MainActor (String) -> Void) async throws -> GlassArt {
        let canPaint = await AppAI.imageRoute() != nil
        var candidates: [(GlassDesign, [String: Data], NSImage)] = []
        var lastError: Error?
        await withTaskGroup(of: Result<(GlassDesign, [String: Data], NSImage), Error>.self) { group in
            for index in 0..<candidateCount {
                group.addTask {
                    do {
                        return .success(try await drawCandidate(spec, appName: appName, about: about, variant: index,
                                                                canPaint: canPaint))
                    } catch { return .failure(error) }
                }
            }
            for await result in group {
                switch result {
                case .success(let made): candidates.append(made)
                case .failure(let error): lastError = error
                }
            }
        }
        guard !candidates.isEmpty else { throw lastError ?? AppAI.Failure(message: "No icon was drawn.") }
        func art(_ index: Int) -> GlassArt { GlassArt(design: candidates[index].0, paintings: candidates[index].1) }
        guard candidates.count > 1, let sheet = Icons.contactSheet(candidates.map(\.2)).representation(using: .png, properties: [:])
        else { return art(0) }
        let prompt = """
        These are \(candidates.count) candidate macOS app icons for an app called "\(appName)", numbered 1 to \
        \(candidates.count) from left to right. Each is shown large, then at its real 32px size on light and on dark. \
        The icon is meant to show: \(spec.subject).
        Judge each against this guide, and against how polished and native it looks next to Apple's own icons:
        \(styleGuide)
        Reply as JSON: {"scores": [<1-10 for each icon, in order>], "best": <number of the best icon, from 1>, \
        "why": "<one short sentence>"}
        """
        struct Verdict: Decodable { let best: Int; let why: String? }
        let image = AppAI.Image(mediaType: "image/png", data: sheet.base64EncodedString())
        guard let (text, _) = try? await AppAI.complete(prompt: prompt, images: [image], system: "", json: true, model: Icons.judgeModel),
              let verdict = try? JSONDecoder().decode(Verdict.self, from: Data(text.utf8)),
              candidates.indices.contains(verdict.best - 1) else { return art(0) }
        if let why = verdict.why { await log("Picked icon \(verdict.best) of \(candidates.count): \(why)") }
        return art(verdict.best - 1)
    }

    /// One design: drawn, painted where it asks for a picture, then looked at and drawn again `rounds` times.
    static func drawCandidate(_ spec: IconSpec, appName: String, about: String, variant: Int, canPaint: Bool,
                              rounds: Int = rounds, model: String = drawModel) async throws -> (GlassDesign, [String: Data], NSImage) {
        let format = canPaint ? format : format + "\nNothing here can paint pictures: use no painted layer."
        let fill = Icons.background(named: spec.background).fill
        var design = try await ask(designPrompt(spec, appName: appName, about: about, variant: variant, format: format,
                                                canPaint: canPaint), images: [], canPaint: canPaint, model: model, fill: fill)
        var paintings = try await paint(design, existing: [:])
        var picture = await tile(GlassArt(design: design, paintings: paintings))
        for _ in 0..<rounds {
            guard let png = picture.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?
                .representation(using: .png, properties: [:]) else { break }
            let encoded = String(data: try JSONEncoder().encode(design), encoding: .utf8) ?? ""
            let look = """
            This is how your icon design for "\(appName)" (\(spec.subject)) renders\(IconTools.found != nil
                ? ", in Icon Composer with the system's Liquid Glass" : " in Lamp's own drawing, which imitates the glass"). \
            Your design was:
            \(encoded)

            Look at it as Apple's icon designers would, against this guide:
            \(styleGuide)
            Find what keeps it from looking like one of Apple's own: shapes that don't read, parts that look flat or \
            cheap, colors that clash or are dull, a translucent layer with nothing different behind it, crowding, a \
            silhouette lost at small size, anything misaligned or off the tile. Then reply with the whole design again, \
            improved, in the same JSON shape. Keep what works.
            """
            let image = AppAI.Image(mediaType: "image/png", data: png.base64EncodedString())
            guard let better = try? await ask(look + "\n\n" + format, images: [image], canPaint: canPaint, model: model,
                                              fill: fill) else { break }
            design = better
            paintings = try await paint(design, existing: paintings)
            picture = await tile(GlassArt(design: design, paintings: paintings))
        }
        return (design, paintings, picture)
    }

    /// The shape of the answer, and how each part is used.
    static let format = """
    The canvas is 1024 by 1024 and is the whole rounded tile; the system cuts its corners, so keep the object between \
    120 and 904 on both axes. Icon Composer gives every layer the system's glass: its edges catch the light from \
    above and it casts a soft shadow on the layers below it.

    Reply as JSON: {"background": "#RRGGBB", "layers": [<two to four layers, back to front>]}, each layer \
    {"name": "<what it is>", "material": "solid|glass|frosted|lens|painted", "color": "#RRGGBB" or null, \
    "opacity": <0.3 to 1>, "svg": "<a complete SVG>", "paint": "<only for a painted layer>"}.
    - svg: viewBox="0 0 1024 1024" width="1024" height="1024", this layer's shape alone, drawn whole even where \
    a layer in front covers it. Only path, circle, ellipse, rect, polygon and g with transforms, filled shapes, and \
    linear or radial gradients in defs; no text, no images, no filters, no masks, no strokes. Cut holes with \
    fill-rule="evenodd".
    - color: set it and the layer is that one color, lit by the system's gentle gradient; the cleanest finish. Leave it \
    null to keep the SVG's own fills, for a piece that glows from within (a radial gradient, lighter at its heart).
    - material: solid is opaque glass; glass is clear and see-through; frosted is see-through and blurred, like \
    acrylic; lens is thick glass that bends and magnifies what's behind it; painted is a rich picture with no glass \
    of its own, painted from "paint" and cut to the svg's shape, for vivid content under a glass piece (a sky, an \
    iridescent disc, a photo). At most one painted layer, and only under glass.
    - opacity: below 1 lets what's behind show through more.
    """

    static func designPrompt(_ spec: IconSpec, appName: String, about: String, variant: Int, format: String = format,
                             canPaint: Bool = true) -> String {
        // Each candidate starts from another idea, so the judge has a real choice.
        let approaches = [
            "Make it the object itself, its parts as stacked glass pieces.",
            "Make it the object on or in front of a bold shape that frames it (a disc, rings, a rounded panel), "
                + "with a translucent piece overlapping the two.",
            canPaint
                ? "Make glass the subject: a painted layer of rich, vivid content (material \"painted\") seen through a thick "
                    + "lens or a frosted panel laid over part of it, the way Preview's icon puts a lens over a picture."
                : "Make glass the subject: a glowing layer (radial gradients in its svg) seen through a thick lens or a "
                    + "frosted panel laid over part of it, the way Preview's icon puts a lens over a picture.",
        ]
        let bg = Icons.background(named: spec.background)
        let ground = bg.isLight || bg.name == "graphite"
            ? "\(bg.fill), with pieces in the object's own vivid color, \(spec.tint), and its shades"
            : "\(bg.fill), with pieces in white and lighter and darker shades of that hue"
        return """
        Design the icon for a macOS 26 app called "\(appName)". About the app:
        \(about.prefix(3000))

        The icon's object: \(spec.subject). You may refine it, but keep it one tangible thing.
        The background: \(ground).
        \(approaches[variant % approaches.count])

        \(styleGuide)

        \(format)
        """
    }

    private static func ask(_ prompt: String, images: [AppAI.Image], canPaint: Bool, model: String,
                            fill: String?) async throws -> GlassDesign {
        var prompt = prompt
        var lastError: Error = AppAI.Failure(message: "The icon design couldn't be read.")
        for _ in 0..<2 {
            do {
                let (text, _) = try await AppAI.complete(prompt: prompt, images: images, system: "You are one of Apple's icon designers.",
                                                         json: true, model: model)
                var design = try JSONDecoder().decode(GlassDesign.self, from: Data(text.utf8))
                // The tile's color was chosen with the app's name and shown since: the drawing keeps it exactly.
                if let fill { design.background = fill }
                if let problem = problem(in: design) { throw AppAI.Failure(message: problem) }
                if !canPaint, design.layers.contains(where: { $0.material == .painted }) {
                    throw AppAI.Failure(message: "there's no way to paint here, so use no painted layer")
                }
                return design
            } catch {
                lastError = error
                prompt += "\n\nYour last reply couldn't be used: \(error.localizedDescription). Reply again, fixed."
            }
        }
        throw lastError
    }

    /// What's wrong with a design before it's rendered, in words for the model.
    static func problem(in design: GlassDesign) -> String? {
        guard Icons.color(hex: design.background) != nil else { return "background must be #RRGGBB" }
        guard (1...4).contains(design.layers.count) else { return "an icon has one to four layers" }
        guard design.layers.filter({ $0.material == .painted }).count <= 1 else { return "at most one painted layer" }
        for layer in design.layers {
            if let color = layer.color, Icons.color(hex: color) == nil { return "\(layer.name): color must be #RRGGBB or null" }
            guard layer.svg.utf8.count <= 200_000 else { return "\(layer.name): the svg is too long; use fewer, simpler shapes" }
            if let refused = refusedPart(of: layer.svg) { return "\(layer.name): the svg may not use \(refused)" }
            guard NSImage(data: Data(layer.svg.utf8)) != nil else { return "\(layer.name): the svg doesn't parse" }
            if layer.material == .painted, (layer.paint ?? "").trimmed.isEmpty { return "\(layer.name): a painted layer needs paint" }
        }
        return nil
    }

    /// What an svg may not hold, as its text says it: anything that reaches outside it (an address, a file, a
    /// picture, a script) or isn't a plain shape. A design can come in a file someone shared, and its svgs are read by
    /// AppKit and Icon Composer, so only shapes and the gradients they're filled with pass.
    static func refusedPart(of svg: String) -> String? {
        let text = svg.lowercased()
        for part in ["<text", "<image", "<script", "<foreignobject", "<use", "<style", "<filter", "<mask", "<pattern",
                     "<!entity", "<!doctype", "<?xml-stylesheet", "javascript:", "data:", "file:"] where text.contains(part) {
            return part
        }
        // The svg namespace is the one address it may name.
        let addresses = text.components(separatedBy: "http").count - 1
        if addresses > text.components(separatedBy: "http://www.w3.org/").count - 1 { return "an address" }
        // Only references within the svg itself, such as a gradient's url(#id).
        for marker in ["href=\"", "href='", "url("] {
            if text.components(separatedBy: marker).dropFirst().contains(where: { !$0.hasPrefix("#") }) { return marker }
        }
        return nil
    }

    /// A painting as Lamp makes them: a picture of at most 2048 pixels a side, read from its header first.
    static func isPainting(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return max(width, height) <= 2048
    }

    // MARK: Painting

    /// Paints what the design's painted layer asks for, cut to its shape; a picture already painted for the same words
    /// and shape is kept.
    static func paint(_ design: GlassDesign, existing: [String: Data]) async throws -> [String: Data] {
        var paintings: [String: Data] = [:]
        for layer in design.layers where layer.material == .painted {
            let key = paintingKey(layer)
            if let kept = existing[key] { paintings[key] = kept; continue }
            let prompt = """
            \(layer.paint ?? ""). Rich, vivid and luminous, smooth and soft, filling the whole frame edge to edge, \
            with no object, border, text or letters in it: it will be seen through glass in an app icon.
            """
            let (data, _) = try await AppAI.image(prompt: prompt, references: [], aspectRatio: "1:1", model: Icons.iconModel)
            guard let cut = masked(data, by: layer.svg) else { throw AppAI.Failure(message: "The painted layer couldn't be cut to its shape.") }
            paintings[key] = cut
        }
        return paintings
    }

    static func paintingKey(_ layer: GlassDesign.Layer) -> String {
        let hash = SHA256.hash(data: Data(((layer.paint ?? "") + "|" + layer.svg).utf8))
        return hash.map { String(format: "%02x", $0) }.joined().prefix(16) + ".png"
    }

    /// The painting stretched over the tile and kept only inside the layer's shape.
    static func masked(_ painting: Data, by svg: String) -> Data? {
        guard let picture = NSImage(data: painting), let shape = NSImage(data: Data(svg.utf8)) else { return nil }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
        shape.draw(in: rect)
        picture.draw(in: rect, from: .zero, operation: .sourceIn, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: The document

    /// Writes the design as an Icon Composer document, each layer a group of its own with its material's settings.
    static func writeDocument(_ design: GlassDesign, paintings: [String: Data], to url: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let assets = url.appendingPathComponent("Assets")
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        var groups: [[String: Any]] = []
        for (index, layer) in design.layers.enumerated() {
            let name = "layer-\(index)"
            var entry: [String: Any] = ["name": layer.name.isEmpty ? name : layer.name]
            if layer.material == .painted, let painting = paintings[paintingKey(layer)] {
                try painting.write(to: assets.appendingPathComponent("\(name).png"))
                entry["image-name"] = "\(name).png"
                entry["glass"] = false
            } else {
                try Data(layer.svg.utf8).write(to: assets.appendingPathComponent("\(name).svg"))
                entry["image-name"] = "\(name).svg"
                entry["glass"] = true
                if let color = layer.color { entry["fill"] = ["automatic-gradient": composerColor(color)] }
            }
            if let opacity = layer.opacity { entry["opacity"] = min(1, max(0.2, opacity)) }
            // Icon Composer lists the top group first.
            groups.insert(group(for: layer.material, layers: [entry]), at: 0)
        }
        let document: [String: Any] = [
            "fill": ["automatic-gradient": composerColor(design.background)],
            "groups": groups,
            "supported-platforms": ["squares": ["macOS"]],
        ]
        try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            .write(to: url.appendingPathComponent("icon.json"))
    }

    /// A material as Icon Composer's group settings, tuned by eye against Apple's own icons.
    static func group(for material: GlassDesign.Material, layers: [[String: Any]]) -> [String: Any] {
        var group: [String: Any] = ["layers": layers, "lighting": "individual",
                                    "shadow": ["kind": "layer-color", "opacity": 0.4], "specular": true]
        switch material {
        case .solid:
            group["translucency"] = ["enabled": false, "value": 0.5]
        case .glass:
            group["translucency"] = ["enabled": true, "value": 0.55]
        case .frosted:
            group["translucency"] = ["enabled": true, "value": 0.45]
            group["blur-material"] = 0.7
        case .lens:
            group["translucency"] = ["enabled": true, "value": 0.25]
            group["refractivity"] = ["enabled": true, "depth": 0.7, "strength": 0.8]
        case .painted:
            group["translucency"] = ["enabled": false, "value": 0.5]
            group["specular"] = false
            group["shadow"] = ["kind": "neutral", "opacity": 0.3]
        }
        return group
    }

    /// The design as macOS shows it, 1024 pixels, full bleed: Icon Composer's rendering with Xcode, else Lamp's own.
    static func tile(_ art: GlassArt) async -> NSImage {
        if let tools = IconTools.found {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-glass-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let doc = dir.appendingPathComponent("AppIcon.icon"), png = dir.appendingPathComponent("tile.png")
            if (try? writeDocument(art.design, paintings: art.paintings, to: doc)) != nil,
               await tools.render(doc, size: 1024, to: png), let image = NSImage(contentsOf: png) {
                return image
            }
        }
        return NSImage(cgImage: drawn(art).cgImage!, size: NSSize(width: 1024, height: 1024))
    }

    /// Lamp's own drawing of a design, for a Mac without Xcode and for a drag: the layers in order on the tile, each
    /// with a soft shadow and the light from above, see-through materials let more of what's behind show, and a
    /// frosted one blurs it a little. Not the system's glass, but the same picture.
    static func drawn(_ art: GlassArt) -> NSBitmapImageRep {
        let side = 1024
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let rect = NSRect(x: 0, y: 0, width: side, height: side)
        NSBezierPath(roundedRect: rect, xRadius: 1024 * 0.225, yRadius: 1024 * 0.225).addClip()
        let ground = Icons.gradient(from: art.design.background)
        NSGradient(colors: [ground.top, ground.bottom])?.draw(in: rect, angle: -90)
        for layer in art.design.layers {
            guard let shape = layerImage(layer, paintings: art.paintings) else { continue }
            let see = [.glass: 0.6, .frosted: 0.75, .lens: 0.8][layer.material] ?? 1.0
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
            shadow.shadowBlurRadius = 18
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            shadow.set()
            shape.draw(in: rect, from: .zero, operation: .sourceOver, fraction: min(1, see * (layer.opacity ?? 1)))
            NSGraphicsContext.restoreGraphicsState()
            guard layer.material != .painted else { continue }
            let light = NSImage(size: rect.size, flipped: false) { r in
                NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0), .clear],
                           atLocations: [0, 0.5, 1], colorSpace: .sRGB)?.draw(in: r, angle: -90)
                shape.draw(in: r, from: .zero, operation: .destinationIn, fraction: 1)
                return true
            }
            light.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSColor.white.withAlphaComponent(0.3).setStroke()
        let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 1024 * 0.225 - 2, yRadius: 1024 * 0.225 - 2)
        rim.lineWidth = 3
        rim.stroke()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// A layer as a picture on the whole tile: its painting, or its svg in its own colors or in its one color.
    private static func layerImage(_ layer: GlassDesign.Layer, paintings: [String: Data]) -> NSImage? {
        if layer.material == .painted { return paintings[paintingKey(layer)].flatMap(NSImage.init(data:)) }
        guard let svg = NSImage(data: Data(layer.svg.utf8)) else { return nil }
        guard let hex = layer.color, let color = Icons.color(hex: hex) else { return svg }
        return NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { r in
            svg.draw(in: r)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
    }

    private static func composerColor(_ hex: String) -> String {
        let c = Icons.color(hex: hex)?.usingColorSpace(.sRGB) ?? .white
        return "srgb:" + [c.redComponent, c.greenComponent, c.blueComponent, 1].map { String(format: "%.5f", $0) }
            .joined(separator: ",")
    }
}
