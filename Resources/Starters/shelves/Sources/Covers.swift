import AppKit

/// Cover pictures, kept as files in the app's own data folder (one per item, named by its id), so they show
/// at once and without a connection after the first time.
enum Covers {
    static let folder: URL = {
        let url = LampStore.folder.appendingPathComponent("Covers")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static func file(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).jpg") }

    static func cached(_ id: UUID) -> NSImage? { NSImage(contentsOf: file(id)) }

    static func remove(_ id: UUID) { try? FileManager.default.removeItem(at: file(id)) }

    /// Fetches and keeps a cover. Nil when there's none, or no connection; the item then shows a drawn one.
    static func download(_ url: URL, for id: UUID) async -> NSImage? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Shelves (a Mac app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data), image.size.width > 10 else { return nil }
        try? data.write(to: file(id), options: .atomic)
        return image
    }

    /// The colour a spine of this cover would be: its most colourful part, as a cover's background or title
    /// usually is, or its average when the cover is mostly black, white or grey.
    static func spineColor(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 6
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        var colours: [NSColor] = []
        for start in stride(from: 0, to: pixels.count, by: 4) {
            let red = CGFloat(pixels[start]) / 255
            let green = CGFloat(pixels[start + 1]) / 255
            let blue = CGFloat(pixels[start + 2]) / 255
            colours.append(NSColor(deviceRed: red, green: green, blue: blue, alpha: 1))
        }
        let vivid = colours.filter { $0.saturationComponent > 0.3 && $0.brightnessComponent > 0.25 }
        func vividness(_ colour: NSColor) -> CGFloat { colour.saturationComponent * colour.brightnessComponent }
        if let best = vivid.max(by: { vividness($0) < vividness($1) }) {
            return best
        }
        let count = CGFloat(colours.count)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        for colour in colours {
            red += colour.redComponent
            green += colour.greenComponent
            blue += colour.blueComponent
        }
        return NSColor(deviceRed: red / count, green: green / count, blue: blue / count, alpha: 1)
    }
}
