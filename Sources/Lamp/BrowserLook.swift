import AppKit
import ImageIO
import UniformTypeIdentifiers

/// How an app's sidebar looks, in Chrome and in Lamp's preview of it. The app says which colors and type are its own
/// (`LampBrowser.Look`, sent as plain values with the rest of its surface); Lamp turns them into every color the
/// sidebar draws with, keeping text readable on them, and the extension only sets those colors. An app that gives no
/// look gets one from its icon, so no two apps' sidebars look the same, whichever Lamp built them.
///
/// The sidebar should read as a part of the app's Mac window, not as a web page in its colors: its background is the
/// window's (neutral, unless the app gives one), the app's color is kept for what the window uses it for (the main
/// button, the offer, focus), and the layout follows the kind of app (`Template`), as the window's does.
@MainActor
enum BrowserLook {
    /// What an app sends: each color as it shows in light and in dark, and its type design.
    struct Requested: Codable, Equatable {
        struct Pair: Codable, Equatable { var light: String; var dark: String }
        var accent: Pair
        var background: Pair?
        var design: String?
        static let designs = ["default", "rounded", "serif", "monospaced"]
        var valid: Bool {
            ([accent] + (background.map { [$0] } ?? [])).allSatisfy { RGB(hex: $0.light) != nil && RGB(hex: $0.dark) != nil }
                && Self.designs.contains(design ?? "default")
        }
    }

    /// A color in sRGB, from 0 to 1.
    struct RGB: Equatable {
        var r: Double, g: Double, b: Double
        init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
        init?(hex: String) {
            guard hex.count == 7, hex.first == "#", let value = Int(hex.dropFirst(), radix: 16) else { return nil }
            self.init(Double(value >> 16 & 255) / 255, Double(value >> 8 & 255) / 255, Double(value & 255) / 255)
        }
        var hex: String {
            func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
            return String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b))
        }
        /// `amount` of the way from this color to `other`.
        func mix(_ other: RGB, _ amount: Double) -> RGB {
            RGB(r + (other.r - r) * amount, g + (other.g - g) * amount, b + (other.b - b) * amount)
        }
        var luminance: Double {
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        func contrast(_ other: RGB) -> Double {
            let (a, b) = (luminance, other.luminance)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        /// This color, moved toward `toward` only as far as it takes to read at `ratio` against `on`.
        func readable(on: RGB, ratio: Double, toward: RGB) -> RGB {
            var step = 0.0, color = self
            while color.contrast(on) < ratio && step < 1 { step += 0.05; color = mix(toward, step) }
            return color
        }
    }

    nonisolated static let white = RGB(1, 1, 1), black = RGB(0, 0, 0)
    /// Lamp's own green, for an app whose icon has no color to take.
    static let fallback = Requested(accent: .init(light: "#3d5736", dark: "#9cc48d"))

    /// How the sidebar is laid out, from the kind of app it belongs to (the first line of its APP.md, which the builder
    /// writes and keeps): a companion's palette and rounded softness, a collection's pictures first, and the plain
    /// window of every other kind.
    enum Template: String {
        case standard, companion, collection
        init(kind: String?) {
            switch kind?.lowercased() {
            case "companion": self = .companion
            case "collection": self = .collection
            default: self = .standard
            }
        }
        static func of(_ project: LampProject) -> Template {
            guard let text = try? String(contentsOf: project.dir.appendingPathComponent("APP.md"), encoding: .utf8) else { return .standard }
            let line = text.split(separator: "\n").prefix(5).first { $0.hasPrefix("Kind:") }
            return Template(kind: line.map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) })
        }
    }

    /// Every color the sidebar draws with, in one appearance.
    struct Palette: Equatable {
        var background, card, line, field, ink, muted, accent, fill, onFill: RGB
        var values: [String: String] {
            ["background": background.hex, "card": card.hex, "line": line.hex, "field": field.hex, "ink": ink.hex,
             "muted": muted.hex, "accent": accent.hex, "fill": fill.hex, "onFill": onFill.hex]
        }

        /// The Mac's own window background and text, which a window without colors of its own shows.
        static let window = (light: RGB(0.937, 0.945, 0.949), dark: RGB(0.118, 0.122, 0.125))

        init(accent chosen: RGB, background given: RGB?, dark: Bool, template: Template = .standard) {
            // A companion's window is washed with its palette; any other window is the Mac's own gray.
            let tint = template == .companion ? (dark ? 0.1 : 0.07) : 0
            let background = given ?? (dark ? Self.window.dark : Self.window.light).mix(chosen, tint)
            let light = background.luminance > 0.35
            let ink = light ? RGB(0.114, 0.114, 0.122) : RGB(0.961, 0.961, 0.969)
            self.background = background
            self.ink = ink
            card = light ? background.mix(white, 0.85) : background.mix(white, 0.07)
            line = background.mix(ink, light ? 0.1 : 0.14)
            field = background.mix(ink, light ? 0.22 : 0.28)
            muted = (light ? RGB(0.431, 0.431, 0.451) : RGB(0.596, 0.596, 0.616)).readable(on: background, ratio: 4.5, toward: ink)
            // As text (the offer, a link) the app's color reads like body text does.
            accent = chosen.readable(on: background, ratio: 4.5, toward: ink)
            // The main button keeps the app's color with a white label, as a Mac's prominent button does, deepened only
            // as far as a bold label needs (3:1); a color too pale for that (a yellow) takes a dark label instead.
            onFill = chosen.mix(black, 0.35).contrast(white) >= 3 ? white : RGB(0.114, 0.114, 0.122)
            fill = chosen.readable(on: onFill, ratio: onFill == white ? 3 : 4.5, toward: onFill == white ? black : white)
        }
    }

    struct Drawn: Equatable {
        var light: Palette
        var dark: Palette
        var design: String
        var template: Template = .standard
        var values: [String: Any] { ["light": light.values, "dark": dark.values, "design": design, "template": template.rawValue] }
    }

    static func drawn(_ requested: Requested, template: Template = .standard) -> Drawn {
        func palette(_ dark: Bool) -> Palette {
            let pick = { (pair: Requested.Pair) in RGB(hex: dark ? pair.dark : pair.light)! }
            return Palette(accent: pick(requested.accent), background: requested.background.map(pick), dark: dark, template: template)
        }
        return Drawn(light: palette(false), dark: palette(true), design: requested.design ?? "default", template: template)
    }

    /// The look an app's sidebar is drawn with: its own, else its icon's color.
    static func drawn(_ look: Requested?, for project: LampProject) -> Drawn {
        drawn(look.flatMap { $0.valid ? $0 : nil } ?? icon(project).accent.map { Requested(accent: .init(light: $0.hex, dark: $0.hex)) } ?? fallback,
              template: Template.of(project))
    }

    /// A section's picture, which the app leaves in its runtime folder under a name made from its contents: a photo
    /// as JPEG, art with a clear background as PNG. Only a plain file of that folder is read, and it's drawn afresh, so
    /// what reaches the sidebar is only ever a picture.
    struct Picture { var data: Data; var isArt: Bool; var dataURL: String { (isArt ? "data:image/png;base64," : "data:image/jpeg;base64,") + data.base64EncodedString() } }
    static func picture(_ name: String, of project: LampProject) -> Picture? {
        guard isPictureName(name) else { return nil }
        let folder = Runtime.macFolder(project).appendingPathComponent("sidebar").resolvingSymlinksInPath()
        for (ext, isArt) in [("jpg", false), ("png", true)] {
            let file = folder.appendingPathComponent(name + "." + ext)
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 4_000_000,
                  let data = try? Data(contentsOf: file), let drawn = redrawn(data, png: isArt) else { continue }
            return Picture(data: drawn, isArt: isArt)
        }
        return nil
    }

    /// A picture drawn again in sRGB and written by ImageIO. AppKit's own PNGs carry a gamma value that Chrome applies
    /// and other viewers don't, which washes the picture out in the sidebar.
    nonisolated static func redrawn(_ data: Data, png: Bool) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              (1...4096).contains(image.width), (1...4096).contains(image.height), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let out = NSMutableData()
        guard let drawn = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(out, (png ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, drawn, png ? nil : [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
    nonisolated static func isPictureName(_ name: String) -> Bool {
        name.count == 16 && name.allSatisfy { "0123456789abcdef".contains($0) }
    }

    /// The app's icon as a small picture for the sidebar's top, and the color it's mostly painted in.
    struct Icon { var png: Data?; var accent: RGB? }
    private static var icons: [String: (stamp: Date, icon: Icon)] = [:]
    static func icon(_ project: LampProject) -> Icon {
        let path = project.installedURL.path
        let stamp = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
        if let kept = icons[project.id], kept.stamp == stamp { return kept.icon }
        var icon = Icon(png: nil, accent: nil)
        if FileManager.default.fileExists(atPath: path),
           let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSWorkspace.shared.icon(forFile: path).draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
            NSGraphicsContext.restoreGraphicsState()
            icon.png = bitmap.representation(using: .png, properties: [:]).flatMap { redrawn($0, png: true) }
            icon.accent = mainColor(bitmap)
        }
        icons[project.id] = (stamp, icon)
        return icon
    }

    /// The hue that covers most of the picture, weighed by how vivid it is; nil for a gray or nearly empty one.
    static func mainColor(_ bitmap: NSBitmapImageRep) -> RGB? {
        var bins = [(weight: Double, r: Double, g: Double, b: Double)](repeating: (0, 0, 0, 0), count: 24)
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.5,
                      c.saturationComponent > 0.25, (0.25...0.97).contains(c.brightnessComponent) else { continue }
                let weight = c.saturationComponent * c.alphaComponent
                let i = min(Int(c.hueComponent * 24), 23)
                bins[i].weight += weight
                bins[i].r += c.redComponent * weight; bins[i].g += c.greenComponent * weight; bins[i].b += c.blueComponent * weight
            }
        }
        // Neighbouring hues are one color: a hue split across two bins still wins over a smaller, single one.
        let scored = bins.indices.map { i in (i, bins[i].weight + 0.5 * (bins[(i + 23) % 24].weight + bins[(i + 1) % 24].weight)) }
        guard let best = scored.max(by: { $0.1 < $1.1 })?.0, bins[best].weight > Double(bitmap.pixelsWide * bitmap.pixelsHigh) * 0.03 else { return nil }
        let w = bins[best].weight
        return RGB(bins[best].r / w, bins[best].g / w, bins[best].b / w)
    }
}
