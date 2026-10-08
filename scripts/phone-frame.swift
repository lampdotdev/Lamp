import AppKit
// swift scripts/phone-frame.swift <out.png> <deviceHeight> <screenCornerFraction> <shot.png>...
// For the website's carousel (see RELEASING.md).
// Each screenshot (simctl --mask alpha) gets a black bezel and a soft shadow; devices sit side by side,
// centred on a transparent 2304×1664 canvas like the Mac slides.
let args = Array(CommandLine.arguments.dropFirst())
let out = args[0], deviceHeight = CGFloat(Double(args[1])!), cornerFraction = CGFloat(Double(args[2])!)
let shots = args.dropFirst(3).map { NSImage(contentsOfFile: $0)! }
let W: CGFloat = 2304, H: CGFloat = 1664, gap: CGFloat = 90
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let sizes = shots.map { shot -> CGSize in
    let s = shot.representations[0]; let aspect = CGFloat(s.pixelsWide) / CGFloat(s.pixelsHigh)
    return CGSize(width: deviceHeight * aspect, height: deviceHeight)
}
let bezel = deviceHeight * 0.022
let total = sizes.reduce(0) { $0 + $1.width + bezel * 2 } + gap * CGFloat(shots.count - 1)
var x = (W - total) / 2
for (shot, screen) in zip(shots, sizes) {
    let body = CGRect(x: x, y: (H - screen.height) / 2 - bezel - 20, width: screen.width + bezel * 2, height: screen.height + bezel * 2)
    let screenCorner = min(screen.width, screen.height) * cornerFraction
    let outer = NSBezierPath(roundedRect: body, xRadius: screenCorner + bezel, yRadius: screenCorner + bezel)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowBlurRadius = 60; shadow.shadowOffset = NSSize(width: 0, height: -28); shadow.set()
    NSColor(white: 0.06, alpha: 1).setFill(); outer.fill()
    NSGraphicsContext.restoreGraphicsState()
    // A thin metal edge, as on the hardware.
    NSColor(white: 0.42, alpha: 1).setStroke(); outer.lineWidth = bezel * 0.16; outer.stroke()
    let screenRect = body.insetBy(dx: bezel, dy: bezel)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screenRect, xRadius: screenCorner, yRadius: screenCorner).addClip()
    shot.draw(in: screenRect)
    NSGraphicsContext.restoreGraphicsState()
    x += body.width + gap
}
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
