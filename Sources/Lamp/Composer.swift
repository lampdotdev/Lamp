import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The chat input: a native text view so Lamp controls the keys and the clipboard.
/// Return sends, Shift/Option/Control-Return insert a new line, and pasting or dropping
/// files or images (e.g. a screenshot) attaches them instead of inserting text.
/// A `suggestion` replaces the placeholder while the composer is empty: Tab accepts it, Escape dismisses it.
struct Composer: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var placeholder: String
    var suggestion: String? = nil
    var onDismissSuggestion: () -> Void = {}
    var isEnabled: Bool
    var focusRequest: Int
    var onSubmit: () -> Void
    var onFiles: ([URL]) -> Void

    static let maxLines: CGFloat = 6
    static let inset: CGFloat = 4
    /// Height of a one-line composer; buttons beside it use this so they line up with the text.
    static let lineHeight = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: NSFont.systemFontSize)) + inset * 2

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = ComposerTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: Composer.inset)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scroll.documentView = textView
        context.coordinator.textView = textView
        textView.onWidthChange = { [weak coordinator = context.coordinator] in coordinator?.updateHeight() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
            coordinator.updateHeight()
        }
        textView.placeholder = suggestion ?? placeholder
        textView.suggestion = suggestion
        textView.onDismissSuggestion = onDismissSuggestion
        textView.setAccessibilityPlaceholderValue(textView.placeholder)
        textView.setAccessibilityHelp(suggestion == nil ? nil : "Press Tab to use the suggestion, or Escape to dismiss it.")
        textView.isEditable = isEnabled
        textView.onSubmit = onSubmit
        textView.onFiles = onFiles
        textView.needsDisplay = true
        if coordinator.lastFocusRequest != focusRequest {
            coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: Composer
        weak var textView: ComposerTextView?
        var lastFocusRequest = Int.min

        init(_ parent: Composer) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            updateHeight()
        }

        /// Grows with the text up to `maxLines`, then scrolls.
        func updateHeight() {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
            layout.ensureLayout(for: container)
            let line = layout.defaultLineHeight(for: textView.font ?? .systemFont(ofSize: NSFont.systemFontSize))
            let used = max(layout.usedRect(for: container).height, line)
            let height = min(used, line * Composer.maxLines) + textView.textContainerInset.height * 2
            if abs(parent.height - height) > 0.5 {
                DispatchQueue.main.async { self.parent.height = height }
            }
        }
    }
}

final class ComposerTextView: NSTextView {
    var placeholder = ""
    var suggestion: String?
    var onDismissSuggestion: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onFiles: (([URL]) -> Void)?
    var onWidthChange: (() -> Void)?

    private var showsSuggestion: Bool { string.isEmpty && suggestion != nil }

    override func keyDown(with event: NSEvent) {
        if showsSuggestion, !hasMarkedText(),
           event.modifierFlags.intersection([.shift, .option, .control, .command]).isEmpty {
            switch event.keyCode {
            case 48: acceptSuggestion(); return            // Tab
            case 53: onDismissSuggestion?(); return        // Escape
            default: break
            }
        }
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn && !hasMarkedText() {   // leave Return alone while an input method is composing
            if event.modifierFlags.intersection([.shift, .option, .control]).isEmpty {
                onSubmit?()
            } else {
                insertNewlineIgnoringFieldEditor(nil)
            }
            return
        }
        super.keyDown(with: event)
    }

    /// The text rewraps when the width changes (the window is resized, or the chat comes back with a draft
    /// in it), so the composer's height has to be measured again, not only when the text changes.
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { onWidthChange?() }
    }

    override func mouseDown(with event: NSEvent) {
        if showsSuggestion, hintRect.contains(convert(event.locationInWindow, from: nil)) {
            window?.makeFirstResponder(self)
            acceptSuggestion()
            return
        }
        super.mouseDown(with: event)
    }

    /// Inserts the suggestion as if typed, so it can be undone and edited before sending.
    private func acceptSuggestion() {
        guard let suggestion, string.isEmpty else { return }
        insertText(suggestion, replacementRange: NSRange(location: 0, length: 0))
    }

    override func paste(_ sender: Any?) {
        if attachFiles(from: .general) { return }
        super.paste(sender)
    }

    /// Images and files count as pasteable. A plain-text view otherwise disables Paste when the clipboard
    /// holds only an image (a screenshot copied with ⌃⇧⌘4), and `paste` is never called.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.png, .tiff, .fileURL]
    }

    /// Don't be a drop target: drops fall through to the chat view's drop handler (`Attachments.load`),
    /// which handles files and images from Finder, browsers, Photos and screenshot thumbnails alike.
    override func updateDragTypeRegistration() {
        unregisterDraggedTypes()
    }

    /// Copied files attach. A copied image (a screenshot copied with ⌃⇧⌘4, or Copy Image in a browser or
    /// Preview) is saved as a PNG and attached.
    private func attachFiles(from pasteboard: NSPasteboard) -> Bool {
        let urls = fileURLs(in: pasteboard)
        if !urls.isEmpty {
            onFiles?(urls)
            return true
        }
        // Only real image data counts, not a link to a picture. Text that comes with a rendering of itself
        // (a spreadsheet's cells) pastes as text; an image that comes with just its address is an image.
        let hasImage = pasteboard.types?.contains { UTType($0.rawValue)?.conforms(to: .image) == true } ?? false
        let text = pasteboard.string(forType: .string)?.trimmed ?? ""
        let textIsItsAddress = !text.contains(where: \.isWhitespace) && URL(string: text)?.scheme?.hasPrefix("http") == true
        guard hasImage, text.isEmpty || textIsItsAddress, let image = NSImage(pasteboard: pasteboard),
              let file = Self.savePasted(image) else { return false }
        onFiles?([file])
        return true
    }

    private func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    static func savePasted(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?
            .representation(using: .png, properties: [:]) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("forge-pasted", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().second())
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        // Two pastes within a second mustn't land on the same file.
        var url = folder.appendingPathComponent("Pasted image \(stamp).png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("Pasted image \(stamp) \(n).png")
            n += 1
        }
        return (try? png.write(to: url)) == nil ? nil : url
    }

    private static let hint = "⇥ to accept"
    private static let hintAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .medium),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]

    private var lineHeight: CGFloat {
        layoutManager?.defaultLineHeight(for: font ?? .systemFont(ofSize: NSFont.systemFontSize)) ?? 17
    }

    /// The "⇥ to accept" key cap at the right end of the first line.
    private var hintRect: NSRect {
        let size = (Self.hint as NSString).size(withAttributes: Self.hintAttributes)
        let width = ceil(size.width) + 10, height = ceil(size.height) + 2
        return NSRect(x: bounds.maxX - width - 2, y: textContainerInset.height + (lineHeight - height) / 2,
                      width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 5
        let x = textContainerInset.width + padding
        var right = bounds.maxX - x
        if suggestion != nil {
            let pill = hintRect
            let path = NSBezierPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            NSColor.quaternaryLabelColor.setFill()
            path.fill()
            NSColor.tertiaryLabelColor.setStroke()
            path.stroke()
            (Self.hint as NSString).draw(at: NSPoint(x: pill.minX + 5, y: pill.minY + 1), withAttributes: Self.hintAttributes)
            right = pill.minX - 8
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        placeholder.draw(with: NSRect(x: x, y: textContainerInset.height, width: max(right - x, 0), height: lineHeight),
                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                         attributes: [.font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                                      .foregroundColor: NSColor.placeholderTextColor,
                                      .paragraphStyle: style])
    }
}

/// A pending attachment in the composer, with a remove button.
struct AttachmentChip: View {
    let url: URL
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            AttachmentThumbnail(url: url, size: 28)
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle).frame(maxWidth: 160, alignment: .leading)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help("Remove")
            }
        }
        .font(.caption)
        .padding(4)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct AttachmentThumbnail: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        if Attachments.isImage(url), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                .frame(width: size, height: size)
        }
    }
}

/// Where attachments live in an app's folder and how they're described to the agent.
enum Attachments {
    /// Item types the chat accepts when something is dropped on it.
    static let dropTypes: [UTType] = [.fileURL, .image]

    /// Turns dropped items into local files: files as-is, and images (from browsers, Photos,
    /// screenshot thumbnails) copied to a temporary file. Calls `completion` on the main thread.
    static func load(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }

        for provider in providers {
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, url.isFileURL { add(url) }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let name = provider.suggestedName
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { file, _ in
                    // The provided file is deleted when this closure returns, so copy it out first.
                    if let file {
                        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("forge-dropped-\(UUID().uuidString)")
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        var target = folder.appendingPathComponent(name.map { ($0 as NSString).deletingPathExtension } ?? "Dropped image")
                        target.appendPathExtension(file.pathExtension.isEmpty ? "png" : file.pathExtension)
                        if (try? FileManager.default.copyItem(at: file, to: target)) != nil { add(target) }
                    }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }

    static let folder = "Attachments"
    static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

    static func isImage(_ url: URL) -> Bool { imageTypes.contains(url.pathExtension.lowercased()) }

    /// Copies files into <app>/Attachments with unique names. Returns the saved names.
    static func save(_ files: [URL], to project: LampProject) -> [String] {
        let fm = FileManager.default
        let dir = project.dir.appendingPathComponent(folder, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var saved: [String] = []
        for file in files {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }   // skip folders and links
            let base = file.deletingPathExtension().lastPathComponent.filter { !"/:\\".contains($0) }
            let ext = file.pathExtension
            var name = ext.isEmpty ? base : "\(base).\(ext)"
            var n = 2
            while fm.fileExists(atPath: dir.appendingPathComponent(name).path) {
                name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
                n += 1
            }
            if (try? fm.copyItem(at: file, to: dir.appendingPathComponent(name))) != nil { saved.append(name) }
        }
        return saved
    }

    /// Files the agent should see directly (pi's `@file`): images, and small text files.
    static func inline(_ names: [String], in project: LampProject) -> [String] {
        names.filter { name in
            let url = project.dir.appendingPathComponent(folder).appendingPathComponent(name)
            if isImage(url) { return true }
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size < 200_000,
                  let data = try? Data(contentsOf: url) else { return false }
            return String(data: data, encoding: .utf8) != nil
        }
    }

    /// Text added to the user's message so the agent knows what's attached and how the app can use it.
    static func note(for names: [String]) -> String {
        guard !names.isEmpty else { return "" }
        let list = names.map { "- \(folder)/\($0)" }.joined(separator: "\n")
        return """


        Attached files (saved in \(folder)/ and bundled inside the app). Images and small text files are \
        included above; read the others with your tools if needed. If the app should use a file, load it with \
        `LampAssets.url("name")`, `LampAssets.image("name")` or `LampAssets.text("name")`:
        \(list)
        """
    }
}
