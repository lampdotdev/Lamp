import AppKit
import CryptoKit

/// The editable description of an app's icon, kept in `icon.json` in the app folder
/// (so it's versioned with the app and the agent can change it on request).
struct IconSpec: Codable, Equatable {
    var symbol: String          // SF Symbol drawn on the instant icon
    var background: [String]    // two hex colours, top → bottom gradient
    var foreground: String      // hex colour of the symbol
    var art_prompt: String?     // what the illustrated artwork shows (generated when an OpenRouter key is set)
}

/// Icons are a hybrid: an instant SF Symbol icon drawn locally, upgraded to generated
/// artwork (via an OpenRouter image model) when a key is available. Generated artwork is
/// cached under .forge/art/ by prompt, so undoing an icon change is instant and free.
enum Icons {
    static let artModels: [(id: String, label: String)] = [
        ("google/gemini-3.1-flash-image", "Nano Banana 2 (Gemini 3.1 Flash Image)"),
        ("google/gemini-3-pro-image", "Nano Banana Pro (Gemini 3 Pro Image, pricier)"),
        ("openai/gpt-image-2.5-sunburst", "GPT Image 2.5 Sunburst (OpenAI, pricier)"),
        ("openai/gpt-image-2.5-flare", "GPT Image 2.5 Flare (OpenAI, pricier)"),
        ("openai/gpt-image-2", "GPT Image 2 (OpenAI, pricier)"),
        ("google/gemini-3.1-flash-lite-image", "Nano Banana 2 Lite (fastest, cheapest)"),
    ]

    /// The OpenRouter image model used for icon artwork (Settings → "Icon artwork").
    static var artModel: String {
        let saved = UserDefaults.standard.string(forKey: "imageModel") ?? ""
        return artModels.contains { $0.id == saved } ? saved : artModels[0].id
    }

    // MARK: Spec

    static func specURL(_ project: ForgeProject) -> URL { project.dir.appendingPathComponent("icon.json") }
    static func icnsURL(_ project: ForgeProject) -> URL { project.dir.appendingPathComponent(".forge/AppIcon.icns") }
    static func previewURL(_ project: ForgeProject) -> URL { project.dir.appendingPathComponent(".forge/icon.png") }

    static func load(_ project: ForgeProject) -> IconSpec? {
        guard let data = try? Data(contentsOf: specURL(project)) else { return nil }
        return try? JSONDecoder().decode(IconSpec.self, from: data)
    }

    static func save(_ spec: IconSpec, for project: ForgeProject) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? encoder.encode(spec).write(to: specURL(project))
    }

    static func artURL(_ project: ForgeProject, prompt: String) -> URL {
        let hash = SHA256.hash(data: Data(prompt.trimmed.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)
        return project.dir.appendingPathComponent(".forge/art/\(hash).png")
    }

    static func cachedArt(_ project: ForgeProject, spec: IconSpec) -> NSImage? {
        guard let prompt = spec.art_prompt, !prompt.trimmed.isEmpty else { return nil }
        return NSImage(contentsOf: artURL(project, prompt: prompt))
    }

    /// Asks the in-app AI model to design an icon from the app's name and APP.md.
    static func design(for project: ForgeProject, avoiding current: IconSpec? = nil) async -> IconSpec {
        let about = (try? String(contentsOf: project.dir.appendingPathComponent("APP.md"), encoding: .utf8)) ?? ""
        var prompt = """
        Design a macOS app icon for an app called "\(project.name)". About the app:
        \(about.prefix(3000))

        Reply as JSON: {"symbol": "<an SF Symbols name that really exists, e.g. note.text, camera.fill, face.smiling>", \
        "background": ["#RRGGBB", "#RRGGBB"], "foreground": "#RRGGBB", \
        "art_prompt": "<one sentence describing a single bold, simple illustrated subject for the icon artwork>"}
        Background is a top-to-bottom gradient, lighter colour first. Foreground must contrast strongly with it.
        """
        if let current, let json = try? String(data: JSONEncoder().encode(current), encoding: .utf8) {
            prompt += "\nMake it clearly different from the current icon: \(json)"
        }
        for _ in 0..<2 {
            guard let (text, _) = try? await AppAI.complete(prompt: prompt, images: [], system: "", json: true),
                  let spec = try? JSONDecoder().decode(IconSpec.self, from: Data(text.utf8)) else { break }
            if NSImage(systemSymbolName: spec.symbol, accessibilityDescription: nil) != nil, spec.background.count >= 2 {
                return spec
            }
            prompt += "\n\"\(spec.symbol)\" is not a valid SF Symbol name. Pick a common one."
        }
        return fallback(for: project.name)
    }

    static func fallback(for name: String) -> IconSpec {
        let palettes = [["#5AC8FA", "#007AFF"], ["#FFB340", "#FF7A00"], ["#7BE495", "#28A745"],
                        ["#C69CFF", "#7B3FE4"], ["#FF8A80", "#E53935"], ["#64D2FF", "#5E5CE6"]]
        let index = abs(name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % palettes.count
        return IconSpec(symbol: "sparkles", background: palettes[index], foreground: "#FFFFFF",
                        art_prompt: "a friendly abstract emblem representing \(name)")
    }

    // MARK: Rendering

    /// Draws the icon on Apple's macOS grid: an 824pt rounded square centred on a 1024pt canvas, with shadow.
    static func render(_ spec: IconSpec, art: NSImage?, size: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high

        let s = CGFloat(size) / 1024
        let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 24 * s
        shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
        shadow.set()
        NSColor.black.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        let colors = spec.background.compactMap(color(hex:))
        NSGradient(colors: colors.count >= 2 ? colors : [.systemBlue, .systemIndigo])?.draw(in: shape, angle: -90)

        if let art {
            // Aspect-fill the artwork into the rounded square.
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            let scale = max(tile.width / art.size.width, tile.height / art.size.height)
            let drawn = NSSize(width: art.size.width * scale, height: art.size.height * scale)
            art.draw(in: NSRect(x: tile.midX - drawn.width / 2, y: tile.midY - drawn.height / 2,
                                width: drawn.width, height: drawn.height))
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let config = NSImage.SymbolConfiguration(pointSize: 420 * s, weight: .medium)
                .applying(.init(paletteColors: [color(hex: spec.foreground) ?? .white]))
            if let symbol = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let box = 500 * s
                let scale = min(box / symbol.size.width, box / symbol.size.height)
                let drawn = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                symbol.draw(in: NSRect(x: tile.midX - drawn.width / 2, y: tile.midY - drawn.height / 2,
                                       width: drawn.width, height: drawn.height))
            }
        }

        // Subtle edge so light icons don't disappear on light backgrounds.
        NSColor.black.withAlphaComponent(0.08).setStroke()
        shape.lineWidth = max(1, 2 * s)
        shape.stroke()

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Writes .forge/AppIcon.icns and .forge/icon.png. Returns the preview image.
    @discardableResult
    static func write(_ spec: IconSpec, art: NSImage?, for project: ForgeProject) throws -> NSImage {
        let fm = FileManager.default
        let iconset = fm.temporaryDirectory.appendingPathComponent("forge-\(UUID().uuidString).iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }

        let sizes = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                     ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
        var preview: Data?
        for (name, pixels) in sizes {
            guard let png = render(spec, art: art, size: pixels).representation(using: .png, properties: [:]) else { continue }
            try png.write(to: iconset.appendingPathComponent("icon_\(name).png"))
            if pixels == 256 { preview = png }
        }

        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL(project).path]
        try iconutil.run()
        iconutil.waitUntilExit()

        if let preview { try preview.write(to: previewURL(project)) }
        return NSImage(contentsOf: previewURL(project)) ?? NSImage()
    }

    // MARK: Artwork

    /// Generates square artwork through OpenRouter's image API, which works the same for every image model
    /// (including image-only ones like GPT Image). Returns PNG data.
    static func generateArt(_ description: String) async throws -> Data {
        let prompt = """
        Artwork for a macOS app icon: \(description).
        Square composition with one bold, simple, centred subject. Rich colourful background that fills the \
        entire canvas edge to edge. Polished, modern, soft lighting. No text, no letters, no border, no frame, \
        no rounded corners, no device mockup, no white margins.
        """
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/images")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(Keychain.openRouterKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Forge", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": artModel,
            "prompt": prompt,
            "n": 1,
            "aspect_ratio": "1:1",
            "output_format": "png",
        ] as [String: Any])

        let (data, response) = try await URLSession.shared.data(for: request)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            throw AppAI.Failure(message: Provider.friendlyError("\(status) \(message)"))
        }
        let images = obj["data"] as? [[String: Any]] ?? []
        guard let base64 = images.first?["b64_json"] as? String,
              let decoded = Data(base64Encoded: base64), NSImage(data: decoded) != nil else {
            throw AppAI.Failure(message: "The image model didn't return a picture.")
        }
        return decoded
    }

    private static func color(hex: String) -> NSColor? {
        var value = hex.trimmed
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = Int(value, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                       blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
