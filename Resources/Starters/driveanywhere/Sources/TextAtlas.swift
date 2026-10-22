import AppKit
import RealityKit

/// Sign lettering drawn once into one texture: each sign is a flat quad showing its own cell.
/// The finished atlas is cached on disk, keyed by everything written on it, so later launches only load a PNG.
/// Laid out and drawn off the main thread (string drawing is safe there); the texture is made on the main thread.
final class TextAtlas {
    struct Cell { let text: String; let background: NSColor; let ink: NSColor; let maxAspect: CGFloat; var rect = CGRect.zero }

    static let cellHeight: CGFloat = 64
    private let maxWidth = 4096
    /// As wide as the lettering needs (a power of two), up to `maxWidth`.
    private var width = 4096
    private(set) var cells: [Cell] = []
    private var index: [String: Int] = [:]

    private static let font = NSFont.systemFont(ofSize: 36, weight: .bold)
    /// Measured once per text, from any thread.
    private static let lock = NSLock()
    private static var widths: [String: CGFloat] = [:]
    /// Atlases the main thread has already made textures of, so their pictures needn't be drawn or loaded again.
    private static var made = Set<UInt64>()

    /// How wide the lettering is, in points at the atlas's size.
    static func width(_ text: String) -> CGFloat {
        lock.lock()
        let known = widths[text]
        lock.unlock()
        if let known { return known }
        let w = ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
        lock.lock(); widths[text] = w; lock.unlock()
        return w
    }

    static func hasTexture(_ key: UInt64) -> Bool { lock.lock(); defer { lock.unlock() }; return made.contains(key) }
    static func noteTexture(_ key: UInt64) { lock.lock(); made.insert(key); lock.unlock() }
    static func forgetTextures() { lock.lock(); made = []; lock.unlock() }

    /// A cell for this text and these colours, shared with any identical sign.
    func cell(_ text: String, background: NSColor, ink: NSColor, maxAspect: CGFloat = 40) -> Int {
        let key = "\(text)|\(background)|\(ink)|\(maxAspect)"
        if let i = index[key] { return i }
        cells.append(Cell(text: text, background: background, ink: ink, maxAspect: maxAspect))
        index[key] = cells.count - 1
        return cells.count - 1
    }

    /// Width over height of a cell, for sizing its quad.
    func aspect(_ i: Int) -> Float { Float(cells[i].rect.width / cells[i].rect.height) }

    /// Where the cell is in the texture, as texture coordinates (v up).
    func uv(_ i: Int) -> (SIMD2<Float>, SIMD2<Float>) {
        let r = cells[i].rect
        let h = CGFloat(height)
        // Half a pixel in, so neighbouring cells never bleed into one another.
        return (SIMD2(Float((r.minX + 2) / CGFloat(width)), Float((r.minY + 2) / h)),
                SIMD2(Float((r.maxX - 2) / CGFloat(width)), Float((r.maxY - 2) / h)))
    }

    private var height = 64

    /// Lays out every cell; returns the key for what's on the atlas.
    func layout() -> UInt64 {
        let pad: CGFloat = 14
        var x: CGFloat = 0, y: CGFloat = 0
        let ch = Self.cellHeight
        for i in cells.indices {
            let w = min(Self.width(cells[i].text) + pad * 2, ch * cells[i].maxAspect)
            if x + w > CGFloat(maxWidth) { x = 0; y += ch }
            cells[i].rect = CGRect(x: x, y: y, width: w, height: ch)
            x += w
        }
        let used = cells.map(\.rect.maxX).max() ?? 1
        width = min(maxWidth, max(256, 1 << Int(ceil(log2(Double(max(used, 1)))))))
        height = max(64, Int(y + ch))
        height = 1 << Int(ceil(log2(Double(height))))

        // The width is part of what's on it (atlases saved before it varied were all 4096 wide).
        return cells.reduce(into: UInt64(1469598103934665603) ^ UInt64(width)) { h, c in
            for b in "\(c.text)|\(c.background)|\(c.ink)|\(c.rect)".utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        }
    }

    /// The atlas's picture: loaded from the cache on disk, or drawn (and saved there).
    func image(_ key: UInt64) -> CGImage? {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("DriveAnywhere", isDirectory: true)
        let file = folder.appendingPathComponent("signs-\(String(key, radix: 16)).png")
        var image: CGImage?
        if let source = CGImageSourceCreateWithURL(file as CFURL, nil) { image = CGImageSourceCreateImageAtIndex(source, 0, nil) }
        if image == nil {
            image = draw()
            if let image, let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
            }
        }
        return image
    }

    private func draw() -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        for c in cells {
            c.background.setFill()
            NSBezierPath(rect: c.rect).fill()
            let text = NSAttributedString(string: c.text, attributes: [.font: Self.font, .foregroundColor: c.ink])
            let size = text.size()
            let room = c.rect.width - 28
            let squeeze = min(1, room / max(size.width, 1))
            ctx.saveGState()
            ctx.translateBy(x: c.rect.midX, y: c.rect.midY)
            ctx.scaleBy(x: squeeze, y: 1)
            text.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2 + 1))
            ctx.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// A flat sign face showing a cell: centred on `center`, facing +z of a frame turned by `yaw`.
    func quad(_ i: Int, into kit: inout MeshKit, center: SIMD3<Float>, yaw: Float, width w: Float, height h: Float, back: Bool) {
        let rot = simd_quatf(angle: yaw + (back ? .pi : 0), axis: [0, 1, 0])
        func p(_ x: Float, _ y: Float) -> SIMD3<Float> { center + rot.act(SIMD3(x, y, 0)) }
        let (a, b) = uv(i)
        kit.quad(p(-w / 2, -h / 2), p(w / 2, -h / 2), p(w / 2, h / 2), p(-w / 2, h / 2),
                 uv: ([a.x, a.y], [b.x, a.y], [b.x, b.y], [a.x, b.y]), outward: rot.act([0, 0, 1]))
    }
}
