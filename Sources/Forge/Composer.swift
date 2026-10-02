import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The chat input: a native text view so Forge controls the keys and the clipboard.
/// Return sends, Shift/Option/Control-Return insert a new line, and pasting or dropping
/// files or images (e.g. a screenshot) attaches them instead of inserting text.
struct Composer: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var placeholder: String
    var isEnabled: Bool
    var focusRequest: Int
    var onSubmit: () -> Void
    var onFiles: ([URL]) -> Void

    static let maxLines: CGFloat = 8

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
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.registerForDraggedTypes([.fileURL])

        scroll.documentView = textView
        context.coordinator.textView = textView
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
        textView.placeholder = placeholder
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
    var onSubmit: (() -> Void)?
    var onFiles: (([URL]) -> Void)?

    override func keyDown(with event: NSEvent) {
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

    override func paste(_ sender: Any?) {
        if attachFiles(from: .general) { return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(in: sender.draggingPasteboard).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(in: sender.draggingPasteboard)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        onFiles?(urls)
        return true
    }

    /// Copied files attach. A bare image (e.g. a screenshot copied with ⌃⇧⌘4) is saved as a PNG and attached.
    private func attachFiles(from pasteboard: NSPasteboard) -> Bool {
        let urls = fileURLs(in: pasteboard)
        if !urls.isEmpty {
            onFiles?(urls)
            return true
        }
        guard pasteboard.string(forType: .string) == nil, let image = NSImage(pasteboard: pasteboard),
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
        let url = folder.appendingPathComponent("Pasted image \(stamp).png")
        return (try? png.write(to: url)) == nil ? nil : url
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 5
        placeholder.draw(at: NSPoint(x: textContainerInset.width + padding, y: textContainerInset.height),
                         withAttributes: [.font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                                          .foregroundColor: NSColor.placeholderTextColor])
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
    static let folder = "Attachments"
    static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

    static func isImage(_ url: URL) -> Bool { imageTypes.contains(url.pathExtension.lowercased()) }

    /// Copies files into <app>/Attachments with unique names. Returns the saved names.
    static func save(_ files: [URL], to project: ForgeProject) -> [String] {
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
    static func inline(_ names: [String], in project: ForgeProject) -> [String] {
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
        `ForgeAssets.url("name")`, `ForgeAssets.image("name")` or `ForgeAssets.text("name")`:
        \(list)
        """
    }
}
