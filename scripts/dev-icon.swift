// Makes the development build's icon: the release icon with DEV written in bold on its paper, near the top right
// corner, so the two Lamps tell apart in the Dock; or Lamp Nightly's, with NIGHTLY there.
// Usage: swift scripts/dev-icon.swift Resources/AppIcon.png out.icns [DEV|NIGHTLY]
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 || arguments.count == 4, let source = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("usage: dev-icon.swift <AppIcon.png> <out.icns> [DEV|NIGHTLY]\n".utf8)); exit(1)
}
let word = arguments.count > 3 ? arguments[3] : "DEV"
// The ink the site prints on the same paper.
let ink = NSColor(srgbRed: 0x1b / 255.0, green: 0x1a / 255.0, blue: 0x17 / 255.0, alpha: 1)
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    source.draw(in: rect)
    // The paper is the icon's top right, above and right of the stripes' L; the word sits in from its corner far
    // enough to clear the curve, and a longer word is set smaller so it stays on the paper.
    let right = size * 0.8, top = size * 0.8, room = size * 0.46
    var font = NSFont.systemFont(ofSize: size * 0.15, weight: .bold)
    let width = NSAttributedString(string: word, attributes: [.font: font]).size().width
    if width > room { font = NSFont.systemFont(ofSize: font.pointSize * room / width, weight: .bold) }
    let text = NSAttributedString(string: word, attributes: [.font: font, .foregroundColor: ink])
    let box = text.size()
    text.draw(at: CGPoint(x: right - box.width, y: top - font.ascender))
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
