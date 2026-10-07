// Makes the development build's icon: the release icon with an orange DEV band across its top,
// so the two Lamps tell apart in the Dock. Usage: swift scripts/dev-icon.swift Resources/AppIcon.png out.icns
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let source = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("usage: dev-icon.swift <AppIcon.png> <out.icns>\n".utf8)); exit(1)
}
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    source.draw(in: rect)
    guard let context = NSGraphicsContext.current?.cgContext,
          let shape = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
    // A DEV band straight across the top of the icon, edge to edge, kept inside the icon's rounded shape:
    // outside the source's own alpha stays transparent.
    context.saveGState()
    context.clip(to: rect, mask: shape)
    // From the very top of the icon down; the lettering sits low enough in it to clear the rounded corners.
    let band = CGRect(x: 0, y: size * 0.78, width: size, height: size * 0.22)
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.025, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    context.setFillColor(NSColor(calibratedRed: 0.96, green: 0.48, blue: 0.1, alpha: 1).cgColor)
    context.fill(band)
    context.setShadow(offset: .zero, blur: 0, color: nil)
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let text = NSAttributedString(string: "DEV", attributes: [
        .font: NSFont.systemFont(ofSize: size * 0.105, weight: .heavy), .foregroundColor: NSColor.white, .paragraphStyle: style,
        .kern: size * 0.008])
    let height = text.size().height
    text.draw(in: CGRect(x: band.minX, y: size * 0.84 - height / 2, width: band.width, height: height))
    context.restoreGState()
    return true
}
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dev-icon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
    try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", arguments[2]]
try! iconutil.run(); iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
