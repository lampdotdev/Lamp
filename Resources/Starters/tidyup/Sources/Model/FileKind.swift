import Foundation
import UniformTypeIdentifiers

/// The kinds of file the rules talk about. Grouping by kind puts each in a folder named `folderName`; a file
/// that is none of these (a font, a script, something unknown) is left where it is.
enum FileKind: String, Codable, CaseIterable, Identifiable {
    case screenshot, image, document, archive, installer, audio, movie

    var id: String { rawValue }

    /// The folder files of this kind are grouped into.
    var folderName: String {
        switch self {
        case .screenshot: return "Screenshots"
        case .image: return "Images"
        case .document: return "Documents"
        case .archive: return "Archives"
        case .installer: return "Installers"
        case .audio: return "Music"
        case .movie: return "Movies"
        }
    }

    /// How the kind reads in a rule's sentence ("Move installers older than…").
    var plural: String {
        switch self {
        case .screenshot: return "screenshots"
        case .image: return "images"
        case .document: return "documents"
        case .archive: return "archives"
        case .installer: return "installers"
        case .audio: return "music and audio"
        case .movie: return "movies"
        }
    }

    /// The start of a reason in the preview ("Installer older than 30 days").
    var singular: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .image: return "Image"
        case .document: return "Document"
        case .archive: return "Archive"
        case .installer: return "Installer"
        case .audio: return "Audio file"
        case .movie: return "Movie"
        }
    }

    var symbol: String {
        switch self {
        case .screenshot: return "camera.viewfinder"
        case .image: return "photo"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .installer: return "shippingbox"
        case .audio: return "music.note"
        case .movie: return "film"
        }
    }

    /// Extensions some Macs don't map to a type that says what it is.
    private static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "pages", "numbers", "key", "xls", "xlsx", "ppt", "pptx", "csv", "txt", "md", "rtf", "epub", "odt",
    ]
    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso"]
    private static let archiveExtensions: Set<String> = ["zip", "gz", "tgz", "tar", "rar", "7z", "bz2", "xz"]

    /// What kind a file is, or nil when it's none of the above. Screenshots are told apart from other images by
    /// the mark macOS leaves on them, or by the names screenshot tools give.
    static func of(_ url: URL) -> FileKind? {
        let ext = url.pathExtension.lowercased()
        // Installers first: a disk image or package also counts as an archive to the type system.
        if installerExtensions.contains(ext) { return .installer }
        if archiveExtensions.contains(ext) { return .archive }
        if documentExtensions.contains(ext) { return .document }
        guard let type = UTType(filenameExtension: ext) else { return nil }
        if type.conforms(to: .image) { return isScreenshot(url) ? .screenshot : .image }
        if type.conforms(to: .movie) { return .movie }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .text) || type.conforms(to: .presentation) || type.conforms(to: .spreadsheet)
            || type.conforms(to: .compositeContent) { return .document }
        return nil
    }

    private static func isScreenshot(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.hasPrefix("screenshot") || name.hasPrefix("screen shot") || name.hasPrefix("cleanshot") { return true }
        guard let item = MDItemCreateWithURL(nil, url as CFURL),
              let flag = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool else { return false }
        return flag
    }
}
