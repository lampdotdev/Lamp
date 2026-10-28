import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A site's icon: the best one it offers, set on a Mac app tile.
enum SiteIcon {
    /// The largest icon the site offers, from its page, its touch icon, or Google's favicon service.
    static func fetch(for url: URL) async -> NSImage? {
        var candidates: [URL] = []
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(WebModel.userAgent, forHTTPHeaderField: "User-Agent")
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            let base = response.url ?? url
            candidates += links(in: html, base: base)
            if let origin = URL(string: "/apple-touch-icon.png", relativeTo: base) { candidates.append(origin.absoluteURL) }
        }
        if let host = url.host(), let google = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=256") {
            candidates.append(google)
        }

        let images = await withTaskGroup(of: (Int, NSImage)?.self) { group in
            for (index, candidate) in candidates.prefix(8).enumerated() {
                group.addTask {
                    guard let (data, _) = try? await URLSession.shared.data(from: candidate),
                          let image = NSImage(data: data), image.isValid else { return nil }
                    return (index, image)
                }
            }
            var found: [(Int, NSImage)] = []
            for await item in group { if let item { found.append(item) } }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
        // The sharpest; a vector one counts as large.
        return images.max { pixels($0) < pixels($1) }
    }

    static func pixels(_ image: NSImage) -> Int {
        let widest = image.representations.map(\.pixelsWide).max() ?? 0
        return widest > 0 ? widest : 512
    }

    /// Icons a page names in its <link> tags, touch icons first.
    private static func links(in html: String, base: URL) -> [URL] {
        var found: [(URL, Int)] = []
        let tags = html.matches(of: try! Regex(#"(?i)<link\b[^>]*>"#)).map { String(html[$0.range]) }
        for tag in tags {
            var attributes: [String: String] = [:]
            for match in tag.matches(of: try! Regex(#"([a-zA-Z-]+)\s*=\s*["']([^"']*)["']"#)) {
                if let key = match[1].substring, let value = match[2].substring {
                    attributes[String(key).lowercased()] = String(value)
                }
            }
            guard let rel = attributes["rel"]?.lowercased(), rel.contains("icon"), !rel.contains("mask"),
                  let href = attributes["href"], let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            let size = attributes["sizes"].flatMap { Int($0.lowercased().split(separator: "x").first ?? "") }
                ?? (rel.contains("apple-touch") ? 180 : 32)
            found.append((url, size))
        }
        return found.sorted { $0.1 > $1.1 }.map(\.0)
    }

    // MARK: The app tile

    /// The site's icon as a Mac app icon, 1024 pixels square: a full-bleed icon fills the tile; a small or
    /// see-through one sits on white.
    static func appIcon(from favicon: NSImage?, name: String) -> CGImage? {
        render(1024) { context in
            let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
            let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowOffset = CGSize(width: 0, height: -12)
            shadow.shadowBlurRadius = 24
            shadow.set()
            NSColor.white.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            if let favicon {
                let large = pixels(favicon) >= 120
                if large, isFullBleed(favicon) {
                    favicon.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
                } else {
                    let side: CGFloat = large ? 540 : 420
                    favicon.draw(in: CGRect(x: 512 - side / 2, y: 512 - side / 2, width: side, height: side),
                                 from: .zero, operation: .sourceOver, fraction: 1)
                }
            } else {
                let hue = CGFloat(name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 360) / 360
                NSColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1).setFill()
                shape.fill()
                let letter = String(name.prefix(1)).uppercased() as NSString
                let font = NSFont.systemFont(ofSize: 440, weight: .semibold)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                let size = letter.size(withAttributes: attributes)
                letter.draw(at: CGPoint(x: 512 - size.width / 2, y: 512 - size.height / 2), withAttributes: attributes)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Whether the icon is a square with no transparent corners, made to be shown as a whole tile.
    private static func isFullBleed(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard rep.pixelsWide > 8, abs(rep.pixelsWide - rep.pixelsHigh) <= 2 else { return false }
        let corners = [(1, 1), (rep.pixelsWide - 2, 1), (1, rep.pixelsHigh - 2), (rep.pixelsWide - 2, rep.pixelsHigh - 2)]
        return corners.allSatisfy { (rep.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? 0) > 0.95 }
    }

    /// Draws at an exact pixel size.
    static func render(_ side: Int, _ draw: (CGContext) -> Void) -> CGImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = CGSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        draw(context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    static func scaled(_ image: CGImage, to side: Int) -> CGImage? {
        render(side) { context in
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// An .icns with every size the Dock and Finder ask for.
    static func icns(_ image: CGImage) -> Data? {
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.icns.identifier as CFString, sizes.count, nil) else { return nil }
        for side in sizes {
            if let scaled = scaled(image, to: side) { CGImageDestinationAddImage(destination, scaled, nil) }
        }
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

extension Library {
    /// Fetches the site's icon and keeps it as its tile, in the background.
    func fetchIcon(for site: Site) {
        Task {
            guard let url = site.address else { return }
            let favicon = await SiteIcon.fetch(for: url)
            guard let tile = SiteIcon.appIcon(from: favicon, name: site.name), let data = SiteIcon.png(tile),
                  var current = self.site(site.id) else { return }
            let file = "\(site.id.uuidString)-\(Int(Date().timeIntervalSince1970)).png"
            try? data.write(to: Library.iconsFolder.appendingPathComponent(file))
            if let old = current.iconFile { try? FileManager.default.removeItem(at: Library.iconsFolder.appendingPathComponent(old)) }
            current.iconFile = file
            save(current)
        }
    }

    /// Uses a picture the person chose as the site's icon.
    func setIcon(_ image: NSImage, for site: Site) {
        guard let tile = SiteIcon.appIcon(from: image, name: site.name), let data = SiteIcon.png(tile),
              var current = self.site(site.id) else { return }
        let file = "\(site.id.uuidString)-\(Int(Date().timeIntervalSince1970)).png"
        try? data.write(to: Library.iconsFolder.appendingPathComponent(file))
        if let old = current.iconFile { try? FileManager.default.removeItem(at: Library.iconsFolder.appendingPathComponent(old)) }
        current.iconFile = file
        save(current)
    }
}
