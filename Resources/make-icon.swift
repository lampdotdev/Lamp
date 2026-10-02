// Draws Forge's own icon: a glowing hammer on a dark anvil-coloured tile.
// Usage: swift Resources/make-icon.swift Resources/AppIcon.icns
import AppKit

func render(_ size: Int) -> NSBitmapImageRep {
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

    // Shadow + dark tile.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.21, blue: 0.27, alpha: 1),
               ending: NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1))!.draw(in: shape, angle: -90)

    // Furnace glow rising from the bottom.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let glow = NSGradient(colors: [NSColor(srgbRed: 1, green: 0.45, blue: 0.1, alpha: 0.75),
                                   NSColor(srgbRed: 1, green: 0.3, blue: 0.05, alpha: 0.25),
                                   NSColor(srgbRed: 1, green: 0.3, blue: 0, alpha: 0)],
                          atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
    glow.draw(fromCenter: NSPoint(x: tile.midX, y: tile.minY - 60 * s), radius: 0,
              toCenter: NSPoint(x: tile.midX, y: tile.minY - 60 * s), radius: 640 * s, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Hammer glyph filled with a molten gradient.
    func glyph(_ name: String, points: CGFloat, in rect: NSRect, colors: [NSColor]) {
        let config = NSImage.SymbolConfiguration(pointSize: points, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let scale = min(rect.width / symbol.size.width, rect.height / symbol.size.height)
        let drawn = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let target = NSRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                            width: drawn.width, height: drawn.height)
        let tinted = NSImage(size: drawn, flipped: false) { bounds in
            symbol.draw(in: bounds)
            NSGradient(colors: colors)!.draw(in: bounds.insetBy(dx: -1, dy: -1), angle: -90)
            return true
        }
        // Keep the gradient only where the symbol is.
        let masked = NSImage(size: drawn, flipped: false) { bounds in
            symbol.draw(in: bounds)
            NSGraphicsContext.current?.compositingOperation = .sourceIn
            tinted.draw(in: bounds, from: .zero, operation: .sourceIn, fraction: 1)
            return true
        }
        NSGraphicsContext.saveGraphicsState()
        let glowShadow = NSShadow()
        glowShadow.shadowColor = NSColor(srgbRed: 1, green: 0.55, blue: 0.1, alpha: 0.8)
        glowShadow.shadowBlurRadius = 40 * s
        glowShadow.set()
        masked.draw(in: target)
        NSGraphicsContext.restoreGraphicsState()
    }
    let molten = [NSColor(srgbRed: 1, green: 0.86, blue: 0.45, alpha: 1),
                  NSColor(srgbRed: 1, green: 0.55, blue: 0.12, alpha: 1)]
    glyph("hammer.fill", points: 460 * s,
          in: NSRect(x: tile.midX - 250 * s, y: tile.midY - 250 * s, width: 500 * s, height: 500 * s), colors: molten)
    glyph("sparkle", points: 160 * s,
          in: NSRect(x: tile.maxX - 270 * s, y: tile.maxY - 270 * s, width: 150 * s, height: 150 * s), colors: molten)

    NSColor.white.withAlphaComponent(0.08).setStroke()
    shape.lineWidth = max(1, 2 * s)
    shape.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Forge-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, pixels) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                       ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(pixels).representation(using: .png, properties: [:])!
        .write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try render(1024).representation(using: .png, properties: [:])!
    .write(to: output.deletingPathExtension().appendingPathExtension("png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
