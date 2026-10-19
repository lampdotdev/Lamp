import AppKit
import UniformTypeIdentifiers

/// The picture of a shared app: its icon and name, and how to open it. It goes into other people's chats with the
/// file and is what Quick Look shows of the file, so it holds nothing but what the file's name and icon already
/// say: never a picture of the app's window, which shows whatever the person keeps in it.
public enum ShareCard {
    /// Wide, as chat apps show a link's picture.
    public static let size = CGSize(width: 1200, height: 630)

    /// Draws the card filling `rect` of a context that isn't flipped.
    public static func draw(_ file: LampFile, in context: CGContext, rect: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        let scale = min(rect.width / size.width, rect.height / size.height)
        context.translateBy(x: rect.minX + (rect.width - size.width * scale) / 2, y: rect.minY + (rect.height - size.height * scale) / 2)
        context.scaleBy(x: scale, y: scale)

        NSColor(srgbRed: 0.965, green: 0.957, blue: 0.937, alpha: 1).setFill()
        CGRect(origin: .zero, size: size).fill()

        let iconRect = CGRect(x: 90, y: (size.height - 420) / 2, width: 420, height: 420)
        if let icon = file.icon {
            context.interpolationQuality = .high
            context.draw(icon, in: iconRect)
        } else {
            // A file from before shared files carried their icon: the icon macOS gives Lamp's files.
            NSWorkspace.shared.icon(for: UTType("dev.lamp.lampapp") ?? .data).draw(in: iconRect)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let title = NSAttributedString(string: file.name, attributes: [
            .font: NSFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: NSColor(white: 0.12, alpha: 1),
            .paragraphStyle: paragraph,
        ])
        let line = NSAttributedString(string: "Open it with Lamp · lamp.dev", attributes: [
            .font: NSFont.systemFont(ofSize: 34, weight: .regular),
            .foregroundColor: NSColor(white: 0.42, alpha: 1),
        ])
        let textX = iconRect.maxX + 70
        let width = size.width - textX - 80
        // Two lines of name at most; anything longer is cut off.
        let titleHeight = min(title.boundingRect(with: CGSize(width: width, height: 1000), options: [.usesLineFragmentOrigin]).height, 180)
        let lineHeight: CGFloat = 44
        let gap: CGFloat = 22
        let top = (size.height + titleHeight + gap + lineHeight) / 2
        title.draw(in: CGRect(x: textX, y: top - titleHeight, width: width, height: titleHeight))
        line.draw(in: CGRect(x: textX, y: top - titleHeight - gap - lineHeight, width: width, height: lineHeight))
    }

    /// The card as a PNG at twice its size, sharp on a Retina screen.
    public static func png(_ file: LampFile) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return nil }
        draw(file, in: context, rect: CGRect(x: 0, y: 0, width: size.width * 2, height: size.height * 2))
        return rep.representation(using: .png, properties: [:])
    }
}
