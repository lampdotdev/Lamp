import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The chat input, in Lamp's window and in the chat inside each app's (the LampSidebar extension), so the two
/// are one and the same: a native text view so Lamp controls the keys and the clipboard.
/// Return sends, Shift/Option/Control-Return insert a new line, and pasting or dropping
/// files or images (e.g. a screenshot) attaches them instead of inserting text.
/// A `suggestion` replaces the placeholder while the composer is empty: Tab accepts it, Escape dismisses it.
/// `onEscape`, when there is one, gets Escape first: it's how a request taken back from the chat is put back.
/// Text set from outside isn't typing, so it has no Undo of its own; dictation's does, one step per phrase:
/// when `dictationUndo`'s phrase changes, Undo brings back the text it holds, the box as it was before it.
public struct Composer: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var placeholder: String
    var suggestion: String? = nil
    var onDismissSuggestion: () -> Void = {}
    var onEscape: (() -> Void)? = nil
    var isEnabled: Bool
    var focusRequest: Int
    var dictationUndo = DictationUndo()
    /// Called when dictation's Undo or Redo changes the box, so listening can stop rather than write over it.
    var onDictationUndo: () -> Void = {}
    var onSubmit: () -> Void
    var onFiles: ([URL]) -> Void

    public init(text: Binding<String>, height: Binding<CGFloat>, placeholder: String, suggestion: String? = nil,
                onDismissSuggestion: @escaping () -> Void = {}, onEscape: (() -> Void)? = nil, isEnabled: Bool, focusRequest: Int,
                dictationUndo: DictationUndo = DictationUndo(), onDictationUndo: @escaping () -> Void = {},
                onSubmit: @escaping () -> Void, onFiles: @escaping ([URL]) -> Void) {
        _text = text
        _height = height
        self.placeholder = placeholder
        self.suggestion = suggestion
        self.onDismissSuggestion = onDismissSuggestion
        self.onEscape = onEscape
        self.isEnabled = isEnabled
        self.focusRequest = focusRequest
        self.dictationUndo = dictationUndo
        self.onDictationUndo = onDictationUndo
        self.onSubmit = onSubmit
        self.onFiles = onFiles
    }

    public static let maxLines: CGFloat = 6
    /// Where the box's window really is on screen, when that isn't where its own window says: inside an app's
    /// sidebar, the box lives in a process of its own whose window macOS keeps out of sight, so the caret it
    /// reports (for the typing indicator, the emoji picker, an input method's candidates) would land at the edge
    /// of the screen. The app hosting it says where it is (`SidebarPlacement`). One place for the process, though
    /// an app may show the chat in more than one window: the app says it again whenever one of its windows comes
    /// to the front, and only the front one has a caret.
    nonisolated(unsafe) public static var hostOrigin: CGPoint?
    public static let inset: CGFloat = 4
    /// Height of a one-line composer; buttons beside it use this so they line up with the text.
    public static let lineHeight = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: NSFont.systemFontSize)) + inset * 2

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
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

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        if textView.string != text {
            if coordinator.lastDictationPhrase != dictationUndo.phrase {
                coordinator.registerUndo(restoring: dictationUndo.restoring)
            }
            textView.string = text
            coordinator.updateHeight()
        }
        textView.placeholder = suggestion ?? placeholder
        textView.suggestion = suggestion
        textView.onDismissSuggestion = onDismissSuggestion
        textView.onEscape = onEscape
        textView.setAccessibilityPlaceholderValue(textView.placeholder)
        textView.setAccessibilityHelp(suggestion == nil ? nil : "Press Tab to use the suggestion, or Escape to dismiss it.")
        textView.isEditable = isEnabled
        textView.onSubmit = onSubmit
        textView.onFiles = onFiles
        textView.needsDisplay = true
        coordinator.lastDictationPhrase = dictationUndo.phrase
        if coordinator.lastFocusRequest != focusRequest {
            coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    /// The dictated phrase being said (`Dictation.phrase`) and the box as it was before it.
    public struct DictationUndo {
        public var phrase = 0
        public var restoring = ""
        public init(phrase: Int = 0, restoring: String = "") {
            self.phrase = phrase
            self.restoring = restoring
        }
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: Composer
        weak var textView: ComposerTextView?
        var lastFocusRequest = Int.min
        var lastDictationPhrase: Int

        init(_ parent: Composer) {
            self.parent = parent
            lastDictationPhrase = parent.dictationUndo.phrase
        }

        /// One Undo step that puts `earlier` back; undoing it registers the Redo.
        func registerUndo(restoring earlier: String) {
            guard let textView, let undoManager = textView.undoManager else { return }
            textView.breakUndoCoalescing()
            undoManager.registerUndo(withTarget: self) { $0.restore(earlier) }
            undoManager.setActionName("Dictation")
        }

        private func restore(_ earlier: String) {
            guard let textView else { return }
            registerUndo(restoring: textView.string)
            textView.string = earlier
            parent.text = earlier
            parent.onDictationUndo()
            updateHeight()
        }

        public func textDidChange(_ notification: Notification) {
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
    var onEscape: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onFiles: (([URL]) -> Void)?
    var onWidthChange: (() -> Void)?

    private var showsSuggestion: Bool { string.isEmpty && suggestion != nil }

    override func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let rect = super.firstRect(forCharacterRange: range, actualRange: actualRange)
        guard let host = Composer.hostOrigin, let window else { return rect }
        return rect.offsetBy(dx: host.x - window.frame.minX, dy: host.y - window.frame.minY)
    }

    override func keyDown(with event: NSEvent) {
        // Left alone while an input method is composing, where Escape belongs to it.
        if event.keyCode == 53, let onEscape, !hasMarkedText(),
           event.modifierFlags.intersection([.shift, .option, .control, .command]).isEmpty {
            onEscape()
            return
        }
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
        let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        .foregroundColor: NSColor.tertiaryLabelColor,
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
            // Only an outline: a filled key cap drew the eye away from the suggestion itself.
            NSColor.quaternaryLabelColor.setStroke()
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

