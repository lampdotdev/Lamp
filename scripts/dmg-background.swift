// Draws the background of the DMG's window in lamp.dev's look: the site's cream paper, the icon's six stripes on
// the slant along the bottom (in the order the site prints them, green to magenta), and an arrow in the site's ink
// from Lamp to Applications. A light paper also keeps Finder's dark icon names readable. Writes one TIFF holding
// both the 1x and the 2x picture, which is what Finder wants for a sharp background on Retina screens.
//
//   swift scripts/dmg-background.swift Resources/DMG
//
// The window size and the icons' positions must match scripts/dmg-settings.py.
import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/DMG")
let window = CGSize(width: 660, height: 400)
let lamp = CGPoint(x: 180, y: 190), applications = CGPoint(x: 480, y: 190)   // icon centers, from the top left

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}
// The site's --color-paper and --color-tape, and its --stripe-0 to --stripe-5.
let paper = color(0xf2ecda), ink = color(0x1b1a17)
let stripes = [0x1f8a4a, 0x7cbf3a, 0xf6b81c, 0xf08a1c, 0xe2402a, 0xd23778].map(color)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(window.width * scale), pixelsHigh: Int(window.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    // In points, so Finder knows which picture is the 2x one. The context then draws in points too.
    rep.size = window
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    // From the top left, like the icon positions and the site's CSS.
    cg.translateBy(x: 0, y: window.height)
    cg.scaleBy(x: 1, y: -1)

    cg.setFillColor(paper)
    cg.fill(CGRect(origin: .zero, size: window))

    // The band of stripes, as the site's headings wear them: a 150° gradient of six hard stops across a wide, short
    // strip, so each stripe rises gently to the right and green starts at the top left. Each stripe is a long
    // quad across the gradient's line (as CSS lays it out), clipped to the band. Finder's title bar takes about 32
    // points off the window's height and the picture's bottom goes under the window's edge, so the stripes are laid
    // out over the 58 points that show, under the icons' names, and the band runs on to the picture's bottom.
    let band = CGRect(x: 0, y: 310, width: window.width, height: 58)
    let angle = 150 * CGFloat.pi / 180
    let along = CGVector(dx: sin(angle), dy: -cos(angle))
    let across = CGVector(dx: -along.dy, dy: along.dx)
    let length = band.width * abs(sin(angle)) + band.height * abs(cos(angle))
    let center = CGPoint(x: band.midX, y: band.midY)
    func point(_ t: CGFloat, _ side: CGFloat) -> CGPoint {
        CGPoint(x: center.x + along.dx * (t - 0.5) * length + across.dx * side,
                y: center.y + along.dy * (t - 0.5) * length + across.dy * side)
    }
    cg.saveGState()
    cg.clip(to: CGRect(x: 0, y: band.minY, width: window.width, height: window.height - band.minY))
    for (i, stripe) in stripes.enumerated() {
        let from = CGFloat(i) / 6, to = CGFloat(i + 1) / 6
        // The first and last stripes run on past the line's ends, so the band's corners are covered.
        let start = i == 0 ? -1 : from, end = i == stripes.count - 1 ? 2 : to
        cg.setFillColor(stripe)
        cg.addLines(between: [point(start, -1000), point(end, -1000), point(end, 1000), point(start, 1000)])
        cg.fillPath()
    }
    cg.restoreGState()

    // A gentle arc between the two icons in the site's ink, flat like the site's printing: no glow.
    let start = CGPoint(x: lamp.x + 84, y: lamp.y), end = CGPoint(x: applications.x - 84, y: applications.y)
    let control = CGPoint(x: (start.x + end.x) / 2, y: start.y - 26)
    let arrow = CGMutablePath()
    arrow.move(to: start)
    arrow.addQuadCurve(to: end, control: control)
    // The head points along the curve's last stretch.
    let heading = atan2(end.y - control.y, end.x - control.x)
    for side in [CGFloat.pi * 0.78, -CGFloat.pi * 0.78] {
        arrow.move(to: end)
        arrow.addLine(to: CGPoint(x: end.x + 15 * cos(heading + side), y: end.y + 15 * sin(heading + side)))
    }
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setStrokeColor(ink)
    cg.setLineWidth(4)
    cg.addPath(arrow)
    cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [render(scale: 1), render(scale: 2)], using: .lzw, factor: 0)!
try! tiff.write(to: folder.appendingPathComponent("background.tiff"))
print("Wrote \(folder.appendingPathComponent("background.tiff").path)")
