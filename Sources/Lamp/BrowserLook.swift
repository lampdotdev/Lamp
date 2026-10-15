import AppKit

/// How an app's sidebar looks, in Chrome and in Lamp's preview of it. The app says which colors and type are its own
/// (`LampBrowser.Look`, sent as plain values with the rest of its surface); Lamp turns them into every color the
/// sidebar draws with, keeping text readable on them, and the extension only sets those colors. An app that gives no
/// look gets one from its icon, so no two apps' sidebars look the same, whichever Lamp built them.
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

    /// Every color the sidebar draws with, in one appearance.
    struct Palette: Equatable {
        var background, card, line, field, ink, muted, accent, fill, onFill: RGB
        var values: [String: String] {
            ["background": background.hex, "card": card.hex, "line": line.hex, "field": field.hex, "ink": ink.hex,
             "muted": muted.hex, "accent": accent.hex, "fill": fill.hex, "onFill": onFill.hex]
        }

        init(accent chosen: RGB, background given: RGB?, dark: Bool) {
            // Without a background of the app's own, the page is just tinted with its color.
            let background = given ?? (dark ? RGB(0.11, 0.11, 0.12).mix(chosen, 0.08) : white.mix(chosen, 0.045))
            let light = background.luminance > 0.35
            let plain = light ? RGB(0.11, 0.11, 0.12) : RGB(0.95, 0.95, 0.96)
            let ink = plain.mix(chosen, 0.12).contrast(background) >= 7 ? plain.mix(chosen, 0.12) : plain
            self.background = background
            self.ink = ink
            card = light ? background.mix(white, 0.65) : background.mix(white, 0.07)
            line = background.mix(ink, 0.14)
            field = background.mix(ink, 0.32)
            muted = ink.mix(background, 0.4).readable(on: background, ratio: 4.5, toward: ink)
            // As text (headings, the offer, a plain button's label) the app's color reads like body text does.
            accent = chosen.readable(on: background, ratio: 4.5, toward: ink)
            // The main button keeps the app's color, deepened only as far as its label needs.
            onFill = white.contrast(chosen) >= black.mix(chosen, 0.1).contrast(chosen) ? white : black.mix(chosen, 0.1)
            fill = chosen.readable(on: onFill, ratio: 4.5, toward: onFill == white ? black : white)
        }
    }

    struct Drawn: Equatable {
        var light: Palette
        var dark: Palette
        var design: String
        var values: [String: Any] { ["light": light.values, "dark": dark.values, "design": design] }
    }

    static func drawn(_ requested: Requested) -> Drawn {
        func palette(_ dark: Bool) -> Palette {
            let pick = { (pair: Requested.Pair) in RGB(hex: dark ? pair.dark : pair.light)! }
            return Palette(accent: pick(requested.accent), background: requested.background.map(pick), dark: dark)
        }
        return Drawn(light: palette(false), dark: palette(true), design: requested.design ?? "default")
    }

    /// The look an app's sidebar is drawn with: its own, else its icon's color.
    static func drawn(_ look: Requested?, for project: LampProject) -> Drawn {
        drawn(look.flatMap { $0.valid ? $0 : nil } ?? icon(project).accent.map { Requested(accent: .init(light: $0.hex, dark: $0.hex)) } ?? fallback)
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
            icon.png = bitmap.representation(using: .png, properties: [:])
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
