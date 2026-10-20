import AppKit
import Vision
import CoreImage

/// Where a bottle's cap is in its picture, as fractions of its size, for drawing the heat band on it.
struct CapBand {
    var y: CGFloat = 0.06
    var x0: CGFloat = 0.3
    var x1: CGFloat = 0.7
}

/// The painted bottles used when there's no photo, and where each one's label and sauce are.
struct BottleStyle {
    var id: String
    var asset: String
    var labelTop: CGFloat
    var labelBottom: CGFloat
    /// How high the sauce reaches when full, as a fraction of the height from the bottom.
    var liquidTop: CGFloat
    var scale: CGFloat = 1

    static let woozy = BottleStyle(id: "woozy", asset: "bottle.png", labelTop: 0.49, labelBottom: 0.83, liquidTop: 0.8)
    static let dasher = BottleStyle(id: "dasher", asset: "dasher.png", labelTop: 0.51, labelBottom: 0.89, liquidTop: 0.78, scale: 0.86)
    static let squeeze = BottleStyle(id: "squeeze", asset: "squeeze.png", labelTop: 0.48, labelBottom: 0.85, liquidTop: 0.64, scale: 0.95)
    static let jar = BottleStyle(id: "jar", asset: "jar.png", labelTop: 0.39, labelBottom: 0.82, liquidTop: 0.83, scale: 0.5)
    static let all = [woozy, dasher, squeeze, jar]

    private static var images: [String: NSImage] = [:]
    var image: NSImage {
        if let image = Self.images[id] { return image }
        let image = LampAssets.image(asset) ?? BottleImages.generic
        Self.images[id] = image
        return image
    }
}

/// Bottle pictures: the cut-out photo saved for each bottle, or the plain bottle for ones without a photo.
enum BottleImages {
    static var folder: URL {
        let url = LampStore.folder.appendingPathComponent("Bottles")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var cache: [String: NSImage] = [:]
    private static var caps: [String: CapBand] = [:]

    static let generic: NSImage = LampAssets.image("bottle.png") ?? NSImage(systemSymbolName: "waterbottle.fill", accessibilityDescription: nil)!

    static func style(for bottle: Bottle) -> BottleStyle? {
        guard let name = bottle.imageName else { return .woozy }
        guard name.hasPrefix("style:") else { return nil }
        return BottleStyle.all.first { "style:" + $0.id == name } ?? .woozy
    }

    /// What stands on the shelf: its label photo, cut out, or a painted bottle until there is one.
    static func image(for bottle: Bottle) -> NSImage {
        if bottle.imageName.map({ $0.hasPrefix("style:") }) ?? true {
            return (BottleStyle.all.first { "style:" + $0.id == bottle.imageName } ?? .woozy).image
        }
        return bottle.imageName.flatMap(file) ?? generic
    }

    private static func file(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let image = NSImage(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        cache[name] = image
        return image
    }

    static func cap(for bottle: Bottle) -> CapBand {
        let key = bottle.imageName ?? "generic"
        if let cap = caps[key] { return cap }
        let cap = findCap(in: image(for: bottle))
        caps[key] = cap
        return cap
    }

    static func save(_ image: NSImage) -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let name = UUID().uuidString + ".png"
        do { try data.write(to: folder.appendingPathComponent(name)) } catch { return nil }
        cache[name] = image
        return name
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        cache[name] = nil
        caps[name] = nil
    }

    /// Scans the picture's outline from the top: the first solid rows are the cap.
    static func findCap(in image: NSImage) -> CapBand {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width > 0 else { return CapBand() }
        let w = 120
        let h = max(10, Int(Double(w) * Double(cg.height) / Double(cg.width)))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return CapBand() }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Row 0 in memory is the top of the picture.
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * w + x) * 4 + 3] }
        guard let top = (0..<h).first(where: { y in (0..<w).contains { alpha($0, y) > 120 } }) else { return CapBand() }
        let row = min(h - 1, top + max(2, Int(Double(h) * 0.035)))
        let solid = (0..<w).filter { alpha($0, row) > 120 }
        guard let x0 = solid.first, let x1 = solid.last, x1 > x0 else { return CapBand() }
        return CapBand(y: CGFloat(row) / CGFloat(h), x0: CGFloat(x0) / CGFloat(w), x1: CGFloat(x1 + 1) / CGFloat(w))
    }
}

/// Upright, reasonably sized pixels for a photo, whatever its orientation.
func uprightImage(_ image: NSImage, maxSide: CGFloat = 1600) -> CGImage? {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return nil }
    let scale = min(1, maxSide / max(size.width, size.height))
    let w = Int(size.width * scale), h = Int(size.height * scale)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage
}

enum Cutout {
    /// Cuts the bottle out of its photo on this Mac, cropped to the bottle.
    static func make(_ image: NSImage) async -> NSImage? {
        guard let cg = uprightImage(image) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> NSImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
            do {
                try handler.perform([request])
                guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
                // The biggest thing in the photo is the bottle; hands and clutter come off.
                var best = result.allInstances
                if result.allInstances.count > 1 {
                    best = IndexSet(integer: largestInstance(result))
                }
                let buffer = try result.generateMaskedImage(ofInstances: best, from: handler, croppedToInstancesExtent: true)
                let ci = CIImage(cvPixelBuffer: buffer)
                guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
                return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
            } catch {
                print("Cutout failed: \(error)")
                return nil
            }
        }.value
    }

    private static func largestInstance(_ result: VNInstanceMaskObservation) -> Int {
        let buffer = result.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return result.allInstances.first ?? 1 }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        var counts: [Int: Int] = [:]
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                let v = Int(bytes[y * row + x])
                if v > 0 { counts[v, default: 0] += 1 }
            }
        }
        return counts.max { $0.value < $1.value }?.key ?? (result.allInstances.first ?? 1)
    }

    /// A barcode in the photo, if there is one.
    static func barcode(in image: NSImage) async -> String? {
        guard let cg = uprightImage(image, maxSide: 2400) else { return nil }
        return await Task.detached { () -> String? in
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.ean13, .ean8, .upce, .code128, .code39, .itf14]
            try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
            return request.results?.compactMap(\.payloadStringValue).first
        }.value
    }
}

/// What the AI read off a bottle.
struct Reading: Decodable {
    var name: String?
    var maker: String?
    var peppers: [String]?
    var ingredients: String?
    var tastes: String?
    var heat: Double?
    var family: String?
    var tag: String?
}

enum BottleReader {
    struct Product { var text: String; var imageURL: URL? }

    /// What Open Food Facts knows about a barcode.
    static func lookUp(_ barcode: String) async -> Product? {
        guard let reply = try? await LampAPI.openfoodfacts.get("api/v2/product/\(barcode).json",
                query: ["fields": "product_name,brands,ingredients_text,quantity,image_front_url"]),
              let json = reply.json as? [String: Any], (json["status"] as? Int) == 1,
              let product = json["product"] as? [String: Any] else { return nil }
        let text = ["product_name", "brands", "quantity", "ingredients_text"].compactMap { key in
            (product[key] as? String).flatMap { $0.isEmpty ? nil : "\(key): \($0)" }
        }.joined(separator: "\n")
        return Product(text: text, imageURL: (product["image_front_url"] as? String).flatMap(URL.init(string:)))
    }

    static func read(photo: NSImage?, name: String? = nil, product: String? = nil) async throws -> Reading {
        let profile = UserDefaults.standard.string(forKey: "tasteProfile") ?? defaultTasteProfile
        let families = FlavorFamily.allCases.map { "\($0.rawValue): \($0.meaning)" }.joined(separator: "\n")
        var source = photo != nil ? "Read the hot sauce bottle in this photo (its label, and any barcode data given)." :
            "Tell me about this hot sauce from what you know of it."
        if let name { source += " The person calls it \"\(name)\"." }
        var images: [NSImage] = []
        if let photo, let cg = uprightImage(photo, maxSide: 1400) { images = [NSImage(cgImage: cg, size: .zero)] }
        let reading = try await LampAI.ask(
            source + " Work out the maker, product name, peppers, ingredients, flavor and approximate heat. " +
            "Use what you know about the product if the label is hard to read; leave a field empty rather than invent. " +
            "Heat is 0 to 10: 2 is jalapeño-mild, 5 is cayenne, 7 is habanero-forward, 9 is ghost pepper, 10 is a superhot extract. " +
            "Family is one key from:\n\(families)\n" +
            "Tastes is a short flavor description (max 12 words). " +
            "Tag is a warm, a little cheeky handwritten note for the person's shelf, max 8 words, written with their taste in mind. " +
            #"Reply as JSON: {"name": "...", "maker": "...", "peppers": ["..."], "ingredients": "...", "tastes": "...", "heat": 6, "family": "<key>", "tag": "..."}"#,
            data: product, images: images,
            system: "You're reading bottles for someone's hot sauce shelf. Their taste: \(profile)",
            as: Reading.self)
        return reading
    }

    /// A second opinion from the decision model on which family it belongs with, so the shelf groups well.
    static func family(for reading: Reading) async -> FlavorFamily? {
        let options = FlavorFamily.allCases.map { "\($0.title): \($0.meaning)" }
        guard let answer = try? await LampAI.choose("Which flavor family does this hot sauce belong with on the shelf?",
                                                    from: options, about: [
            "name": reading.name ?? "", "maker": reading.maker ?? "", "peppers": (reading.peppers ?? []).joined(separator: ", "),
            "ingredients": reading.ingredients ?? "", "tastes": reading.tastes ?? "",
        ]), (answer.confidence ?? 0) > 0.55, let choice = answer.choice,
              let index = options.firstIndex(of: choice) else { return nil }
        return FlavorFamily.allCases[index]
    }
}
