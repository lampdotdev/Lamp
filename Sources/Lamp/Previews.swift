import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Small copies of pictures, for where the full file would cost too much: the agent's conversation and a
/// version's thumbnail. The full-size files stay as they are: a picture of a window is what the person sees,
/// and a painted asset is what the app shows.
enum Previews {
    /// The long side of a picture handed to the agent. A window or phone screen is still readable at this
    /// size, and a JPEG of it is a tenth of the PNG: a model takes in hundreds before the request is too big
    /// to send, where the full pictures ran out at a few dozen (Anthropic refuses a request whose images come
    /// to more than 30 MB).
    static let agentMaxPixels = 1280
    static let agentQuality = 0.7

    /// Writes a JPEG of `source` no larger than `maxPixels` on its long side. False if the source can't be read
    /// or the copy can't be written.
    @discardableResult
    static func write(_ source: URL, to destination: URL, maxPixels: Int, quality: Double) -> Bool {
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(output)
    }

    /// The copy of `picture` the agent is shown, written under the app's runtime folder (`.lamp/runtime/previews`),
    /// which the privacy rule for pictures covers like the screenshots beside it. The full picture itself when
    /// no copy could be made, so a model is never left without the picture it asked for.
    static func forAgent(_ picture: URL, in project: LampProject) -> URL {
        let name = picture.deletingPathExtension().lastPathComponent
        // Art and screenshots share the folder; a file's own folder keeps two of one name apart.
        let prefix = picture.deletingLastPathComponent().lastPathComponent == "Assets" ? "art-" : ""
        let preview = Runtime.folder(project).appendingPathComponent("previews/\(prefix)\(name).jpg")
        return write(picture, to: preview, maxPixels: agentMaxPixels, quality: agentQuality) ? preview : picture
    }

    /// The MIME type of a picture file the agent is handed, by its extension.
    static func mimeType(of path: String) -> String {
        UTType(filenameExtension: (path as NSString).pathExtension)?.preferredMIMEType ?? "image/png"
    }
}
