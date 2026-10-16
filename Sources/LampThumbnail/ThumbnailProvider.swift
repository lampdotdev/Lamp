import QuickLookThumbnailing
import LampFileLook

/// The icon Finder, Mail and Messages show for a shared app: the app's own icon, read out of the file. A file
/// without one (shared by an earlier Lamp) keeps the icon macOS gives every Lamp file.
@objc(ThumbnailProvider)
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        guard let icon = LampFile(contentsOf: request.fileURL)?.icon else {
            handler(nil, CocoaError(.fileReadCorruptFile))
            return
        }
        let side = min(request.maximumSize.width, request.maximumSize.height)
        handler(QLThumbnailReply(contextSize: CGSize(width: side, height: side)) { context in
            // The context is in pixels (the size asked for times the screen's scale), so it's filled by its own size.
            context.interpolationQuality = .high
            context.draw(icon, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
            return true
        }, nil)
    }
}
