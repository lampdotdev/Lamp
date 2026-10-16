import Foundation
import Compression
import CoreGraphics
import ImageIO

/// What Quick Look and the share picture show of a shared app: its name and its
/// icon as drawn when it was shared. Read straight out of the .lampapp (a zip) without unpacking it, since the
/// Quick Look extensions run sandboxed and only ever see the one file, and a file from anyone must not be able
/// to make them write, run or hold much of anything.
public struct LampFile {
    public let name: String
    public let icon: CGImage?

    /// The drawn icon's name inside the file. Lamp reads the app's own icon from icon.json when it opens a file;
    /// this copy is only for looking at the file before then.
    public static let iconEntry = "icon.png"
    static let manifestEntry = "lamp-app.json"

    public init(name: String, icon: CGImage?) {
        self.name = name
        self.icon = icon
    }

    /// Nil when the file isn't a readable Lamp app file.
    public init?(contentsOf url: URL) {
        guard let zip = Zip(url),
              let manifest = zip.data(of: Self.manifestEntry, limit: 64 * 1024),
              let object = (try? JSONSerialization.jsonObject(with: manifest)) as? [String: Any],
              let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        self.name = String(name.prefix(80))
        // A picture no larger than Lamp writes there, its size read from the header before it's decoded.
        self.icon = zip.data(of: Self.iconEntry, limit: 4 * 1024 * 1024).flatMap { data -> CGImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width <= 1024, height <= 1024 else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
    }
}

/// Just enough of the zip format to take one small entry out of a file Lamp made with ditto: the central
/// directory's sizes are trusted only up to a limit, and only stored or deflated entries are read.
struct Zip {
    private let data: Data

    init?(_ url: URL) {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 64 * 1024 * 1024,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        self.data = data
    }

    func data(of name: String, limit: Int) -> Data? {
        guard let entry = entries().first(where: { $0.name == name }),
              entry.uncompressed <= limit, entry.compressed <= limit else { return nil }
        // The local header repeats the name and may carry an extra field of another length.
        let local = entry.offset
        guard u32(local) == 0x0403_4b50, let nameLength = u16(local + 26), let extraLength = u16(local + 28) else { return nil }
        let start = local + 30 + nameLength + extraLength
        guard start + entry.compressed <= data.count else { return nil }
        let body = data.subdata(in: start..<start + entry.compressed)
        switch entry.method {
        case 0: return entry.compressed == entry.uncompressed ? body : nil
        case 8: return inflate(body, size: entry.uncompressed)
        default: return nil
        }
    }

    private struct Entry { let name: String, method: Int, compressed: Int, uncompressed: Int, offset: Int }

    private func entries() -> [Entry] {
        // The end record is in the last 64 KB (its comment is at most that long).
        let floor = max(0, data.count - 22 - 65_535)
        guard data.count >= 22,
              let end = stride(from: data.count - 22, through: floor, by: -1).first(where: { u32($0) == 0x0605_4b50 }),
              let count = u16(end + 10), let start = u32(end + 16) else { return [] }
        var entries: [Entry] = []
        var at = Int(start)
        for _ in 0..<min(count, 5000) {
            guard u32(at) == 0x0201_4b50, let method = u16(at + 10), let compressed = u32(at + 20),
                  let uncompressed = u32(at + 24), let nameLength = u16(at + 28), let extraLength = u16(at + 30),
                  let commentLength = u16(at + 32), let offset = u32(at + 42),
                  at + 46 + nameLength <= data.count else { break }
            let name = String(decoding: data[(data.startIndex + at + 46)..<(data.startIndex + at + 46 + nameLength)], as: UTF8.self)
            entries.append(Entry(name: name, method: method, compressed: Int(compressed), uncompressed: Int(uncompressed), offset: Int(offset)))
            at += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private func inflate(_ body: Data, size: Int) -> Data? {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            body.withUnsafeBytes { input in
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                          input.bindMemory(to: UInt8.self).baseAddress!, body.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == size ? output : nil
    }

    private func u16(_ at: Int) -> Int? {
        guard at >= 0, at + 2 <= data.count else { return nil }
        let i = data.startIndex + at
        return Int(data[i]) | Int(data[i + 1]) << 8
    }

    private func u32(_ at: Int) -> UInt32? {
        guard at >= 0, at + 4 <= data.count else { return nil }
        let i = data.startIndex + at
        return UInt32(data[i]) | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]) << 16 | UInt32(data[i + 3]) << 24
    }
}
