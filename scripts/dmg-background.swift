// Draws the background of the DMG's window: the night sky over the dunes (Resources/DMG/sky.png), with a
// golden arrow from Lamp to Applications. Writes one TIFF holding both the 1x and the 2x picture, which is
// what Finder wants for a sharp background on Retina screens.
//
//   swift scripts/dmg-background.swift Resources/DMG
//
// The window size and the icons' positions must match scripts/dmg-settings.py.
import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/DMG")
let window = CGSize(width: 660, height: 400)
let lamp = CGPoint(x: 180, y: 190), applications = CGPoint(x: 480, y: 190)   // icon centers, from the top left

func render(scale: CGFloat) -> NSBitmapImageRep {
    let sky = NSImage(contentsOf: folder.appendingPathComponent("sky.png"))!
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(window.width * scale), pixelsHigh: Int(window.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    // In points, so Finder knows which picture is the 2x one. The context then draws in points too.
    rep.size = window
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    let cg = NSGraphicsContext.current!.cgContext

    // The whole picture, resized to the window rather than cropped (it's drawn at nearly the window's shape).
    sky.draw(in: CGRect(origin: .zero, size: window))

    // A gentle arc between the two icons, in the gold of the stars, with a soft glow.
    func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: window.height - p.y) }
    let start = flip(CGPoint(x: lamp.x + 84, y: lamp.y)), end = flip(CGPoint(x: applications.x - 84, y: applications.y))
    let control = CGPoint(x: (start.x + end.x) / 2, y: start.y + 26)
    let gold = NSColor(srgbRed: 1.0, green: 0.80, blue: 0.45, alpha: 1)
    let arrow = CGMutablePath()
    arrow.move(to: start)
    arrow.addQuadCurve(to: end, control: control)
    // The head points along the curve's last stretch.
    let angle = atan2(end.y - control.y, end.x - control.x)
    for side in [CGFloat.pi * 0.8, -CGFloat.pi * 0.8] {
        arrow.move(to: end)
        arrow.addLine(to: CGPoint(x: end.x + 14 * cos(angle + side), y: end.y + 14 * sin(angle + side)))
    }
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setShadow(offset: .zero, blur: 10, color: gold.withAlphaComponent(0.8).cgColor)
    cg.setStrokeColor(gold.withAlphaComponent(0.9).cgColor)
    cg.setLineWidth(3)
    cg.addPath(arrow)
    cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [render(scale: 1), render(scale: 2)], using: .lzw, factor: 0)!
try! tiff.write(to: folder.appendingPathComponent("background.tiff"))
print("Wrote \(folder.appendingPathComponent("background.tiff").path)")
