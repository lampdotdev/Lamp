import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Small copies of pictures, for where the full file would cost too much: the agent's conversation and a
/// version's thumbnail. The full-size files stay as they are: a picture of a window is what the person sees,
/// and a painted asset is what the app shows.
enum Previews {
    /// The long side of a painted picture handed to the agent: enough to judge it by, a fortieth of the PNG.
    /// A screenshot keeps its pixels: `use_app` takes its points as pixels in the picture, and the app
    /// (`LampDriver`) and the simulator driver turn them into points on the screen at the scale the picture was
    /// taken at (at most 1024 pixels on the long side for a Mac window, point size for an iPhone), so a smaller
    /// picture would land every click short of its target. JPEG alone makes it a sixth of the PNG; at 0.6 a window's
    /// words still read clearly, at about 110 KB for a busy Mac window where 0.7 at 1400 pixels was about 240 KB.
    static let artMaxPixels = 1024
    static let agentQuality = 0.6

    /// A JPEG of `source`, no larger than `maxPixels` on its long side when given, else the same size. Nil if the
    /// source can't be read.
    static func jpeg(of source: URL, maxPixels: Int?, quality: Double) -> Data? {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else { return nil }
        return jpeg(of: imageSource, maxPixels: maxPixels, quality: quality)
    }

    /// The same, of a picture's bytes already read.
    static func jpeg(of data: Data, maxPixels: Int?, quality: Double) -> Data? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return jpeg(of: imageSource, maxPixels: maxPixels, quality: quality)
    }

    private static func jpeg(of imageSource: CGImageSource, maxPixels: Int?, quality: Double) -> Data? {
        let image: CGImage?
        if let maxPixels {
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                           kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
            image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options)
        } else {
            image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        }
        let data = NSMutableData()
        guard let image, let output = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(output) ? data as Data : nil
    }

    /// Writes a JPEG of `source`, a picture in the app's folder, at `destination`, a path `destination(for:…)` gave.
    /// False if the source can't be read or the copy can't be written. The source is read as `AppFile` reads, never
    /// through a link, since the copy lands where the agent can read it.
    @discardableResult
    static func write(_ source: URL, in project: LampProject, to destination: URL, maxPixels: Int?, quality: Double) -> Bool {
        guard let picture = AppFile.read(source, in: project),
              let data = jpeg(of: picture, maxPixels: maxPixels, quality: quality) else { return false }
        // Atomic: the file is written beside its place and moved over whatever is there, a link included,
        // so nothing is ever written through one.
        return (try? data.write(to: destination, options: .atomic)) != nil
    }

    /// Where a copy named `name` may be written under `folder` (a path inside the app's folder, such as
    /// `.lamp/runtime/previews`), made if needed. The app's folder is the agent's to write, and Lamp writes
    /// here unconfined, so the folder has to be a real folder in the app's own, not a link leading out, and
    /// the file a plain file or nothing: the same rule as `Store.artDestination`.
    static func destination(for name: String, under folder: String, in project: LampProject) -> URL? {
        let fm = FileManager.default
        let root = project.realDir
        /// Whether a path inside the app's folder is where it says, with no link along it leading out.
        func isReal(_ url: URL) -> Bool {
            let inside = String(url.standardizedFileURL.path.dropFirst(project.dir.standardizedFileURL.path.count))
            return url.resolvingSymlinksInPath().standardizedFileURL.path == root.path + inside
        }
        let url = project.dir.appendingPathComponent(folder)
        if let type = (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType {
            guard type == .typeDirectory else { return nil }
        } else {
            // Made only under a real folder of the app's: the nearest one that exists is checked first, so the
            // missing part is never made through a linked ancestor.
            var existing = url.deletingLastPathComponent()
            while existing.path.count > project.dir.path.count, !fm.fileExists(atPath: existing.path) {
                existing = existing.deletingLastPathComponent()
            }
            guard isReal(existing), (try? fm.createDirectory(at: url, withIntermediateDirectories: true)) != nil else { return nil }
        }
        guard isReal(url) else { return nil }
        let file = url.appendingPathComponent(name)
        if let type = (try? fm.attributesOfItem(atPath: file.path))?[.type] as? FileAttributeType, type != .typeRegular { return nil }
        return file
    }

    /// The copy of `picture` the agent is shown, written under the app's runtime folder (`.lamp/runtime/previews`),
    /// which the privacy rule for pictures covers like the screenshots beside it. The full picture itself when
    /// no copy could be made, so a model is never left without the picture it asked for; nil when the picture can't
    /// be read as the app's own (`AppFile`), which is then not the agent's to see.
    static func forAgent(_ picture: URL, in project: LampProject) -> URL? {
        guard AppFile.attributes(picture, in: project) != nil else { return nil }
        let name = picture.deletingPathExtension().lastPathComponent
        // Art and screenshots share the folder; a file's own folder keeps two of one name apart.
        let art = picture.deletingLastPathComponent().lastPathComponent == "Assets"
        guard let preview = destination(for: (art ? "art-" : "") + name + ".jpg", under: ".lamp/runtime/previews", in: project),
              write(picture, in: project, to: preview, maxPixels: art ? artMaxPixels : nil, quality: agentQuality)
        else { return picture }
        return preview
    }

    /// The MIME type of a picture file the agent is handed, by its extension.
    static func mimeType(of path: String) -> String {
        UTType(filenameExtension: (path as NSString).pathExtension)?.preferredMIMEType ?? "image/png"
    }
}
