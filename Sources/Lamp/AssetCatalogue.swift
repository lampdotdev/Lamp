import Compression
import CoreText
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Ready-made models, sprites, tiles, icons and textures the agent can bring into an app with the `assets` tool: free
/// work by people who publish it for anyone to use (Kenney, Quaternius, KayKit, ambientCG, Google's Poly). Lamp ships
/// only the index (Resources/asset-catalogue.json, written by scripts/update-assets.py, which reads every licence from
/// where the work is published and pins every file by its SHA-256), never the files: one is fetched into the app's
/// folder when the agent chooses it, checked against its hash, and credited in the wish's credits.json, so sharing,
/// publishing and Put on GitHub carry its credit as they carry any other.
///
/// Lamp itself fetches and writes the files, as data: nothing fetched is run, opened or made executable, and only the
/// files the index names (a .glb, a picture, an atlas's XML) are taken out of an archive, by Lamp's own reading of it.
enum AssetCatalogue {
    /// The licences an asset may have to be offered: work anyone may use, change and share without asking. CC-BY asks for
    /// credit, which Lamp writes. Anything else in the index (a licence it was refreshed with by mistake) is never offered.
    static let licences: Set<String> = ["CC0-1.0", "CC-BY-3.0", "CC-BY-4.0"]

    static func isUsable(_ licence: String?) -> Bool { licence.map(licences.contains) ?? false }
    static func needsCredit(_ licence: String) -> Bool { licence.hasPrefix("CC-BY") }

    // MARK: The index

    /// One asset as the agent sees it, its pack's facts filled in.
    struct Item: Equatable {
        var id: String
        var name: String
        var kind: String
        var pack: String
        var packName: String
        var author: String
        var licence: String
        var style: String
        /// Credited as its pack ("City Kit by Kenney") or as itself ("Taxi by Poly by Google"): a CC-BY asset always as itself.
        var creditAsPack: Bool
        /// Where a person reads about it: its own page, else its pack's.
        var page: String
        var packSource: String
        /// Its one file, for an asset fetched as itself.
        var file: URL?
        var sha256: String?
        /// The archive its files are in, and their paths there, for one taken out of a pack's archive.
        var archive: Archive?
        var members: [String]
        var bytes: Int
        var triangles: Int?
        var box: [Double]?
        var texture: Int?
        var animations: [String]
        var pixels: [Int]?
        var atlas: Bool
        var notes: String?
        var tags: [String]
        var thumb: URL?

        var isModel: Bool { file?.pathExtension.lowercased() == "glb" }
    }

    struct Archive: Equatable, Decodable {
        var url: URL
        var sha256: String
        var bytes: Int
    }

    private struct Index: Decodable {
        var packs: [Pack]
        struct Pack: Decodable {
            var id: String
            var name: String
            var author: String
            var source: String
            var kind: String
            var style: String
            var license: String?
            var credit: String?
            var thumb: String?
            var archive: Archive?
            var assets: [Asset]
        }
        struct Asset: Decodable {
            var id: String
            var name: String
            var kind: String
            var file: String?
            var files: [String]?
            var bytes: Int
            var sha256: String?
            var thumb: String?
            var page: String?
            var author: String?
            var license: String?
            var tags: [String]?
            var tris: Int?
            var box: [Double]?
            var texture: Int?
            var animations: [String]?
            var pixels: [Int]?
            var atlas: String?
            var notes: String?
            var archive: Archive?
        }
    }

    /// The index in Lamp's bundle.
    static let all: [Item] = Bundle.main.resourceURL
        .flatMap { try? Data(contentsOf: $0.appendingPathComponent("asset-catalogue.json")) }
        .map(items) ?? []

    /// The assets in an index that may be offered: a licence Lamp allows, an https address, a hash to check it by, and
    /// file paths that stay inside where they're put. One that fails any of these is left out, not repaired.
    static func items(from data: Data) -> [Item] {
        guard let index = try? JSONDecoder().decode(Index.self, from: data) else { return [] }
        var result: [Item] = []
        for pack in index.packs {
            guard isID(pack.id) else { continue }
            for asset in pack.assets {
                let licence = asset.license ?? pack.license
                guard isUsable(licence), let licence, asset.id.hasPrefix(pack.id + "/"), isID(String(asset.id.dropFirst(pack.id.count + 1))) else { continue }
                let file = asset.file.flatMap(https)
                let archive = asset.archive ?? pack.archive
                let members = asset.files ?? []
                if let file {
                    guard asset.sha256.map(isHash) == true, ["glb", "png", "jpg"].contains(file.pathExtension.lowercased()) else { continue }
                } else {
                    guard let archive, https(archive.url.absoluteString) != nil, isHash(archive.sha256), !members.isEmpty,
                          members.allSatisfy(isMember) else { continue }
                }
                let page = (asset.page.flatMap(https) ?? https(pack.source))?.absoluteString ?? ""
                result.append(Item(
                    id: asset.id, name: asset.name, kind: asset.kind, pack: pack.id, packName: pack.name,
                    author: asset.author ?? pack.author, licence: licence, style: pack.style,
                    creditAsPack: pack.credit != "asset" && !needsCredit(licence), page: page,
                    packSource: https(pack.source)?.absoluteString ?? page,
                    file: file, sha256: file == nil ? nil : asset.sha256, archive: file == nil ? archive : nil,
                    members: file == nil ? members : [], bytes: asset.bytes, triangles: asset.tris, box: asset.box,
                    texture: asset.texture, animations: asset.animations ?? [], pixels: asset.pixels,
                    atlas: asset.atlas == "xml", notes: asset.notes, tags: asset.tags ?? [],
                    // A Poly Pizza model's picture is beside its file, under the same name.
                    thumb: (asset.thumb ?? pack.thumb).flatMap(https)
                        ?? file.flatMap { $0.pathExtension == "glb" ? $0.deletingPathExtension().appendingPathExtension("webp") : nil }))
            }
        }
        return result
    }

    private static func https(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.host?.contains(".") == true else { return nil }
        return url
    }
    private static func isHash(_ text: String) -> Bool { text.count == 64 && text.allSatisfy(\.isHexDigit) }
    private static func isID(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 80 && text.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }
    /// A file inside an archive that may be taken out: a picture or an atlas, by a plain relative path.
    private static func isMember(_ path: String) -> Bool {
        guard Credits.validPath(path) != nil, !path.contains("\\") else { return false }
        return ["png", "jpg", "xml"].contains((path as NSString).pathExtension.lowercased())
    }

    // MARK: Finding

    /// The kinds the tool takes: each a word in the index, and two that gather several.
    static let modelKinds: Set<String> = ["model", "building", "vehicle", "character", "nature", "prop"]
    static let flatKinds: Set<String> = ["sprites", "tileset", "ui", "icons"]

    static func matches(_ item: Item, kind: String?) -> Bool {
        guard let kind = kind?.lowercased(), !kind.isEmpty, kind != "any" else { return true }
        if kind == "model" || kind == "3d" { return modelKinds.contains(item.kind) }
        if kind == "2d" { return flatKinds.contains(item.kind) }
        return item.kind == kind
    }

    /// The assets that fit the words best, most fitting first: a word in its name counts most, then its kind, its pack
    /// and style, its tags, notes and animations. Plurals match their singular ("cars" finds "Car").
    static func search(_ words: String, kind: String?, in items: [Item] = all) -> [Item] {
        let wanted = terms(words)
        var scored: [(Item, Int)] = []
        for item in items where matches(item, kind: kind) {
            let name = Set(terms(item.name)), packWords = Set(terms(item.packName + " " + item.style + " " + item.author))
            let more = Set(terms(item.tags.joined(separator: " ") + " " + (item.notes ?? "") + " " + item.animations.joined(separator: " ")))
            var score = 0
            for word in wanted {
                if name.contains(word) { score += 4 }
                if terms(item.kind).contains(word) { score += 2 }
                if packWords.contains(word) { score += 2 }
                if more.contains(word) { score += 1 }
            }
            if wanted.isEmpty || score > 0 { scored.append((item, score)) }
        }
        return scored.enumerated().sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }.map(\.element.0)
    }

    static func terms(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map { word in
            var word = String(word)
            if word.count > 3, word.hasSuffix("ies") { word = String(word.dropLast(3)) + "y" }
            else if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { word.removeLast() }
            return word
        }
    }

    // MARK: What the slowest place allows

    /// What one model may cost on the slowest place the app is shown: its triangles, and its pictures' longest side.
    /// A model is one of many in a scene, so it gets a small share of the place's frame (`Rules.gamePlaces`).
    struct Budget: Equatable {
        var place: String
        var triangles: Int
        var texture: Int
    }

    static func budget(for app: LampProject) -> Budget {
        let places = app.openPlaces
        if places.contains(.tv) { return Budget(place: "a Samsung or LG TV", triangles: 3_000, texture: 1024) }
        if places.contains(.androidTV) { return Budget(place: "a Google TV or Fire TV stick", triangles: 4_000, texture: 1024) }
        if places.contains(.device) {
            let model = GameKit.isGame(app) ? GameKit.xboxModel(for: app) : nil
            if let model, model.localizedCaseInsensitiveContains("Series") {
                return Budget(place: "the \(model)", triangles: 20_000, texture: 2048)
            }
            return Budget(place: "an Xbox One", triangles: 8_000, texture: 1024)
        }
        if places.contains(where: \.isAndroid) { return Budget(place: "a mid-range Android phone", triangles: 8_000, texture: 1024) }
        if places.contains(.ios) { return Budget(place: "an iPhone", triangles: 15_000, texture: 2048) }
        return Budget(place: "this Mac", triangles: 60_000, texture: 4096)
    }

    // MARK: How an asset reads to the agent

    static func line(_ item: Item, budget: Budget?) -> String {
        var facts: [String] = [item.kind]
        if let triangles = item.triangles { facts.append("\(triangles.formatted()) triangles") }
        if let box = item.box, box.count == 6 {
            let size = (0..<3).map { box[$0 + 3] - box[$0] }
            facts.append(size.map { String(format: $0 < 10 ? "%.2g" : "%.0f", $0) }.joined(separator: "×") + " units (x×y×z)")
        }
        if !item.animations.isEmpty { facts.append("\(item.animations.count) animations") }
        if let pixels = item.pixels, pixels.count == 2 { facts.append("\(pixels[0])×\(pixels[1]) px" + (item.atlas ? " with an XML atlas" : "")) }
        facts.append(size(item.bytes))
        if let budget, let triangles = item.triangles, triangles > budget.triangles { facts.append("too heavy for \(budget.place)") }
        let notes = item.notes.map { ": \($0)" } ?? ""
        return "- \(item.id): \(item.name)\(notes) (\(facts.joined(separator: ", "))). \(item.packName) by \(item.author), \(item.licence); \(item.style)."
    }

    static func size(_ bytes: Int) -> String {
        bytes >= 1 << 20 ? String(format: "%.1f MB", Double(bytes) / Double(1 << 20)) : "\(max(1, bytes >> 10)) KB"
    }

    // MARK: Fetching

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Where fetched archives are kept between fetches, by their hash: in Lamp's own folder, which commands can't write.
    static var downloads: URL { Edition.supportFolder.appendingPathComponent("Asset Downloads") }

    /// The bytes at `url`, checked against `sha256`. An archive already fetched is read from Lamp's folder, and checked again.
    static func fetch(_ url: URL, sha256: String, bytes: Int, keep: Bool) async throws -> Data {
        let kept = downloads.appendingPathComponent(sha256 + "." + url.pathExtension.prefix(5))
        if keep, let data = try? Data(contentsOf: kept), hash(data) == sha256 { return data }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.setValue("Lamp", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure(message: "its source answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard hash(data) == sha256 else {
            throw Failure(message: "it has changed at its source since Lamp checked it, so it wasn't used")
        }
        if keep {
            try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
            try? data.write(to: kept, options: .atomic)
        }
        return data
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// One asset's files as they'll be written, by their path under the asset folder: a model as `<pack>/<name>.glb`, an
    /// archive's files as `<pack>/<file name>`. Pictures larger than the budget are made smaller first, a model's inside it;
    /// an atlas's sheet is kept as it is, since its XML gives places in pixels.
    static func files(of item: Item, budget: Budget) async throws -> [(path: String, data: Data, note: String?)] {
        let slug = String(item.id.split(separator: "/").last ?? "")
        if let file = item.file, let sha256 = item.sha256 {
            if let triangles = item.triangles, triangles > budget.triangles {
                throw Failure(message: "it has \(triangles.formatted()) triangles, more than one model should have on \(budget.place) (about \(budget.triangles.formatted()))")
            }
            var data = try await fetch(file, sha256: sha256, bytes: item.bytes, keep: false)
            var note: String?
            if item.isModel, let texture = item.texture, texture > budget.texture,
               let smaller = GLB.shrinkingPictures(data, to: budget.texture) {
                data = smaller
                note = "its pictures were made \(budget.texture) px at most, for \(budget.place)"
            }
            return [("\(item.pack)/\(slug).\(file.pathExtension.lowercased())", data, note)]
        }
        guard let archive = item.archive else { throw Failure(message: "the index names no file for it") }
        let zip = try await fetch(archive.url, sha256: archive.sha256, bytes: archive.bytes, keep: true)
        var result: [(String, Data, String?)] = []
        for member in item.members {
            guard var data = Zip.read(member, from: zip) else { throw Failure(message: "its archive has no \(member)") }
            var note: String?
            let ext = (member as NSString).pathExtension.lowercased()
            if !item.atlas, ext != "xml", let smaller = Pictures.shrinking(data, to: budget.texture) {
                data = smaller
                note = "made \(budget.texture) px at most, for \(budget.place)"
            }
            result.append(("\(item.pack)/\((member as NSString).lastPathComponent)", data, note))
        }
        return result
    }

    /// The credit for what was fetched: one entry for each pack of CC0 work, one for each asset that asks for credit as
    /// itself (CC-BY, or one found on its own), each with the files of it in the wish.
    static func credits(for fetched: [(item: Item, files: [String])]) -> Credits {
        var sources: [Credits.Source] = []
        for (item, files) in fetched {
            let name = item.creditAsPack ? item.packName : item.name
            let url = item.creditAsPack ? item.packSource : item.page
            if let index = sources.firstIndex(where: { $0.name == name && $0.url == url && $0.license == item.licence }) {
                sources[index].files = (sources[index].files ?? []) + files.filter { !(sources[index].files ?? []).contains($0) }
            } else {
                sources.append(Credits.Source(name: name, author: item.author, url: url, license: item.licence, adapted: false, files: files))
            }
        }
        return Credits(upstream: sources)
    }

    // MARK: Pictures for the agent

    /// The found assets' pictures in one sheet, numbered as they're listed, so the agent can judge their style together.
    /// Nil when none could be fetched.
    static func sheet(of items: [Item]) async -> Data? {
        let shown = Array(items.prefix(12))
        var pictures: [Int: CGImage] = [:]
        await withTaskGroup(of: (Int, CGImage?).self) { group in
            for (index, item) in shown.enumerated() {
                guard let thumb = item.thumb else { continue }
                group.addTask {
                    var request = URLRequest(url: thumb, timeoutInterval: 20)
                    request.setValue("Lamp", forHTTPHeaderField: "User-Agent")
                    guard let (data, _) = try? await URLSession.shared.data(for: request), data.count < 4 << 20,
                          let source = CGImageSourceCreateWithData(data as CFData, nil) else { return (index, nil) }
                    let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256] as CFDictionary
                    return (index, CGImageSourceCreateThumbnailAtIndex(source, 0, options))
                }
            }
            for await (index, picture) in group { if let picture { pictures[index] = picture } }
        }
        guard !pictures.isEmpty else { return nil }
        let cell = 256, columns = min(4, shown.count), rows = (shown.count + columns - 1) / columns
        guard let context = CGContext(data: nil, width: columns * cell, height: rows * cell, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0.92, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: columns * cell, height: rows * cell))
        for index in shown.indices {
            let x = (index % columns) * cell, y = (rows - 1 - index / columns) * cell
            if let picture = pictures[index] {
                let scale = min(Double(cell - 8) / Double(picture.width), Double(cell - 8) / Double(picture.height))
                let w = Double(picture.width) * scale, h = Double(picture.height) * scale
                context.draw(picture, in: CGRect(x: Double(x) + (Double(cell) - w) / 2, y: Double(y) + (Double(cell) - h) / 2, width: w, height: h))
            }
            context.setFillColor(CGColor(gray: 0, alpha: 0.7))
            context.fill(CGRect(x: x, y: y + cell - 34, width: 40, height: 34))
            let label = NSAttributedString(string: "\(index + 1)", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)])
            context.textPosition = CGPoint(x: x + 8, y: y + cell - 26)
            CTLineDraw(CTLineCreateWithAttributedString(label), context)
        }
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

// MARK: - Reading what's fetched

/// Files out of a .zip, read by Lamp itself: the central directory, then each file stored or deflated. Only what the
/// index names is read, never written anywhere but where Lamp puts it, so a path in the archive can't lead elsewhere.
enum Zip {
    /// The most one file may unpack to, so an archive can't fill the disk.
    static let largest = 64 << 20

    static func read(_ name: String, from zip: Data) -> Data? {
        let bytes = [UInt8](zip)
        func u16(_ at: Int) -> Int { at + 2 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : 0 }
        func u32(_ at: Int) -> Int { at + 4 <= bytes.count ? u16(at) | u16(at + 2) << 16 : 0 }
        // The end of the central directory: the last record with its signature, within the last 64 KB and a comment.
        var end = bytes.count - 22
        while end >= max(0, bytes.count - 65_557), u32(end) != 0x0605_4b50 { end -= 1 }
        guard end >= 0, u32(end) == 0x0605_4b50 else { return nil }
        var at = u32(end + 16)
        for _ in 0..<u16(end + 10) {
            guard u32(at) == 0x0201_4b50 else { return nil }
            let method = u16(at + 10), packed = u32(at + 20), size = u32(at + 24)
            let nameLength = u16(at + 28), extra = u16(at + 30), comment = u16(at + 32), local = u32(at + 42)
            guard at + 46 + nameLength <= bytes.count else { return nil }
            let entry = String(decoding: bytes[(at + 46)..<(at + 46 + nameLength)], as: UTF8.self)
            at += 46 + nameLength + extra + comment
            guard entry == name else { continue }
            guard size <= largest, u32(local) == 0x0403_4b50 else { return nil }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + packed <= bytes.count else { return nil }
            let stored = Data(bytes[start..<(start + packed)])
            switch method {
            case 0: return stored.count == size ? stored : nil
            case 8:
                var out = Data(count: size)
                let written = out.withUnsafeMutableBytes { target in
                    stored.withUnsafeBytes { source in
                        compression_decode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, size,
                                                  source.bindMemory(to: UInt8.self).baseAddress!, packed, nil, COMPRESSION_ZLIB)
                    }
                }
                return written == size ? out : nil
            default: return nil
            }
        }
        return nil
    }
}

/// Pictures made smaller for a slow place.
enum Pictures {
    /// The picture with its longer side at most `limit`, in its own format; nil when it's already within it or can't be read.
    static func shrinking(_ data: Data, to limit: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              max(width, height) > limit, let type = CGImageSourceGetType(source) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: limit,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
}

/// A binary glTF with the pictures inside it made smaller: each picture's bytes replaced, and the binary chunk laid out
/// again with every view moved to its new place. Meshes, animations and materials are as they were.
enum GLB {
    static func shrinkingPictures(_ data: Data, to limit: Int) -> Data? {
        let bytes = [UInt8](data)
        func u32(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 }
        guard bytes.count > 28, u32(0) == 0x4654_6c67, u32(16) == 0x4E4F_534A else { return nil }
        let jsonLength = u32(12)
        let binAt = 20 + jsonLength
        guard binAt + 8 <= bytes.count, u32(binAt + 4) == 0x004E_4942 else { return nil }
        let binLength = u32(binAt)
        guard binAt + 8 + binLength <= bytes.count,
              var gltf = (try? JSONSerialization.jsonObject(with: Data(bytes[20..<binAt]))) as? [String: Any],
              var views = gltf["bufferViews"] as? [[String: Any]] else { return nil }
        let bin = Array(bytes[(binAt + 8)..<(binAt + 8 + binLength)])
        // Only views every picture has to itself, in the one buffer the file carries.
        let accessorViews = Set((gltf["accessors"] as? [[String: Any]] ?? []).compactMap { $0["bufferView"] as? Int })
        var replaced: [Int: [UInt8]] = [:]
        for image in gltf["images"] as? [[String: Any]] ?? [] {
            guard let view = image["bufferView"] as? Int, view < views.count, !accessorViews.contains(view),
                  (views[view]["buffer"] as? Int ?? 0) == 0 else { continue }
            let offset = views[view]["byteOffset"] as? Int ?? 0, length = views[view]["byteLength"] as? Int ?? 0
            guard offset + length <= bin.count, let smaller = Pictures.shrinking(Data(bin[offset..<(offset + length)]), to: limit) else { continue }
            replaced[view] = [UInt8](smaller)
        }
        guard !replaced.isEmpty, views.allSatisfy({ ($0["buffer"] as? Int ?? 0) == 0 }) else { return nil }
        var newBin: [UInt8] = []
        for index in views.indices {
            while newBin.count % 4 != 0 { newBin.append(0) }
            let offset = views[index]["byteOffset"] as? Int ?? 0, length = views[index]["byteLength"] as? Int ?? 0
            guard offset + length <= bin.count else { return nil }
            let part = replaced[index] ?? Array(bin[offset..<(offset + length)])
            views[index]["byteOffset"] = newBin.count
            views[index]["byteLength"] = part.count
            newBin += part
        }
        while newBin.count % 4 != 0 { newBin.append(0) }
        gltf["bufferViews"] = views
        if var buffers = gltf["buffers"] as? [[String: Any]], !buffers.isEmpty {
            buffers[0]["byteLength"] = newBin.count
            gltf["buffers"] = buffers
        }
        guard var json = try? JSONSerialization.data(withJSONObject: gltf, options: [.withoutEscapingSlashes]).map({ $0 }) else { return nil }
        while json.count % 4 != 0 { json.append(0x20) }
        func le(_ value: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        let total = 12 + 8 + json.count + 8 + newBin.count
        return Data(le(0x4654_6c67) + le(2) + le(total) + le(json.count) + le(0x4E4F_534A) + json + le(newBin.count) + le(0x004E_4942) + newBin)
    }
}
