import SwiftUI
import AppKit
import QuickLook
import UniformTypeIdentifiers
import LampSidebarKit

/// An attachment, in the composer (with a remove button) or the chat. Clicking it shows it in Quick Look.
struct AttachmentChip: View {
    let url: URL
    /// The attachments it was sent or is going with, which the arrow keys step through in Quick Look.
    var siblings: [URL] = []
    var onRemove: (() -> Void)?

    var body: some View {
        ChatLook.Chip(onRemove: onRemove) {
            AttachmentPreview(url: url, siblings: siblings) {
                ChatLook.ChipLabel(name: url.lastPathComponent) { AttachmentThumbnail(url: url, size: 28) }
            }
        }
    }
}

/// Shows an attachment in Quick Look when clicked, the way Finder does with the space bar, instead of
/// opening another app over Lamp. The arrow keys go through `siblings`, and the right-click menu still
/// opens it or shows it in the Finder.
struct AttachmentPreview<Label: View>: View {
    let url: URL
    var siblings: [URL] = []
    @ViewBuilder let label: Label
    @State private var previewing: URL?

    var body: some View {
        Button { previewing = url } label: { label.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .help(url.lastPathComponent)
            .quickLookPreview($previewing, in: siblings.contains(url) ? siblings : [url])
            .contextMenu {
                Button("Quick Look") { previewing = url }
                Button("Open") { NSWorkspace.shared.open(url) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
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

    /// Where saved attachments are, from their names.
    static func urls(_ names: [String], in project: LampProject) -> [URL] {
        names.map { project.dir.appendingPathComponent(folder).appendingPathComponent($0) }
    }

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
    /// pi gets the files with the prompt (`@file`), so they're "above"; Claude Code reads them itself, images
    /// included; Codex reads them with Lamp's `read` tool, which shows images too (and `-i` only works on a
    /// first turn, not a resumed one).
    /// `inlined`: pi was given the images and small text files with the request itself (`inline`), as it is for a
    /// request that starts a turn, but not for a message it takes while it works.
    static func note(for names: [String], engine: Engine = Builder.engine, inlined: Bool = true) -> String {
        guard !names.isEmpty else { return "" }
        let list = names.map { "- \(folder)/\($0)" }.joined(separator: "\n")
        let how: String
        switch engine {
        case .pi where !inlined: how = "Read each of them with your read tool before you go on; it shows pictures too."
        case .pi: how = "Images and small text files are included above; read the others with your tools if needed."
        case .claude: how = "Read each of them with your Read tool before you start; it shows pictures too."
        case .codex: how = "Read each of them with Lamp's `read` tool before you start; it shows pictures too."
        }
        return """


        Attached files (saved in \(folder)/ and bundled inside the app). \(how) If the app should use a file, \
        load it with `LampAssets.url("name")`, `LampAssets.image("name")` or `LampAssets.text("name")`:
        \(list)
        """
    }
}
