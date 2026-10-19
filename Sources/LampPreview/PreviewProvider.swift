import QuickLookUI
import LampFileLook

/// What pressing Space on a shared app shows: the same picture that's sent with it (`ShareCard`), drawn from the
/// file's name and icon.
@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        guard let file = LampFile(contentsOf: request.fileURL) else { throw CocoaError(.fileReadCorruptFile) }
        let size = CGSize(width: ShareCard.size.width / 2, height: ShareCard.size.height / 2)
        return QLPreviewReply(contextSize: size, isBitmap: false) { context, _ in
            ShareCard.draw(file, in: context, rect: CGRect(origin: .zero, size: size))
        }
    }
}
