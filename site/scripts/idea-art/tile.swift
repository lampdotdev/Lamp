// Puts generated icon art on Lamp's icon tile, the way Icons.drawnTile does: the object cut out (Vision, when the
// art isn't already see-through), on a soft gradient rounded square with a highlight, a shadow and a light rim.
// Usage: tile <art.png> <top hex> <bottom hex> <light 0|1> <out.png> <size> [object]
// With "object" it writes the object alone instead, centered on a transparent square, for the page's categories.
import AppKit
import Vision
import CoreImage

let a = CommandLine.arguments
let data = try! Data(contentsOf: URL(fileURLWithPath: a[1]))
func hex(_ s: String) -> NSColor {
    var v: UInt64 = 0; Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
let light = a[4] == "1"
let size = Int(a[6])!

func transparentShare(_ rep: NSBitmapImageRep) -> Double {
    var clear = 0, n = 0
    for i in 0..<24 { for j in 0..<24 {
        let x = i * (rep.pixelsWide - 1) / 23, y = j * (rep.pixelsHigh - 1) / 23
        if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 1) < 0.1 { clear += 1 }; n += 1
    } }
    return Double(clear) / Double(n)
}

var art: CGImage
let rep = NSBitmapImageRep(data: data)!
if rep.hasAlpha && transparentShare(rep) > 0.05 {
    art = rep.cgImage!
} else {
    let src = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
    let handler = VNImageRequestHandler(cgImage: src)
    let request = VNGenerateForegroundInstanceMaskRequest()
    try! handler.perform([request])
    let obs = request.results!.first!
    let buf = try! obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: true)
    let ci = CIImage(cvPixelBuffer: buf)
    art = CIContext().createCGImage(ci, from: ci.extent)!
}
// Crop to what's visible, so every object is sized by itself, not by its empty margins.
func visibleBox(_ img: CGImage) -> CGRect {
    let w = img.width, h = img.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h { for x in 0..<w where p[(y * w + x) * 4 + 3] > 24 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    guard maxX > minX else { return CGRect(x: 0, y: 0, width: w, height: h) }
    // Rows in the bitmap run top to bottom; cropping wants the same.
    return CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
}
art = art.cropping(to: visibleBox(art)) ?? art

if a.count > 7 && a[7] == "object" {
    let square = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: square)
    NSGraphicsContext.current?.imageInterpolation = .high
    let fit = CGFloat(size) / CGFloat(max(art.width, art.height))
    let w = CGFloat(art.width) * fit, h = CGFloat(art.height) * fit
    NSImage(cgImage: art, size: NSSize(width: art.width, height: art.height))
        .draw(in: NSRect(x: (CGFloat(size) - w) / 2, y: (CGFloat(size) - h) / 2, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    try! square.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[5]))
    exit(0)
}

let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
NSGraphicsContext.current?.imageInterpolation = .high
let rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
let shape = NSBezierPath(roundedRect: rect, xRadius: 1024 * 0.225, yRadius: 1024 * 0.225)
shape.addClip()
NSGradient(colors: [hex(a[2]), hex(a[3])])!.draw(in: rect, angle: -90)
NSGradient(colors: [NSColor.white.withAlphaComponent(light ? 0.5 : 0.22), .clear])!
    .draw(in: NSRect(x: 0, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(light ? 0.18 : 0.3)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
let side: CGFloat = 1024 * 0.66
let scale = min(side / CGFloat(art.width), side / CGFloat(art.height))
let dw = CGFloat(art.width) * scale, dh = CGFloat(art.height) * scale
NSImage(cgImage: art, size: NSSize(width: art.width, height: art.height))
    .draw(in: NSRect(x: 512 - dw / 2, y: 512 - dh / 2, width: dw, height: dh))
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.35).setStroke()
let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 1024 * 0.225 - 2, yRadius: 1024 * 0.225 - 2)
rim.lineWidth = 3
rim.stroke()
NSGraphicsContext.restoreGraphicsState()

let final = NSImage(size: NSSize(width: size, height: size))
let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
NSGraphicsContext.current?.imageInterpolation = .high
out.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
_ = final
try! small.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[5]))
