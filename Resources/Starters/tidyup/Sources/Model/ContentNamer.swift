import AppKit

/// Names files by what's in them: the text in them (Live Text for screenshots and pictures, a PDF's text, a
/// text file's lines) goes to the AI, which answers with a short name. A picture with no text in it is shown
/// to the AI instead. Names are remembered by file and date, so a preview asks once per file, not every time
/// it's drawn. When the AI isn't set up or fails, files simply keep their names.
@MainActor
final class ContentNamer {
    static let shared = ContentNamer()

    /// "path|modified" → the name read (without extension), or "" when the file had nothing to go by.
    private var names: [String: String] = LampStore.load([String: String].self, from: "contentNames") ?? [:]
    /// Set when the AI couldn't answer, until the next preview asks again.
    private(set) var unavailable = false

    func name(of file: URL) -> String? { names[Self.key(file)] }

    func resetAvailability() { unavailable = false }

    /// Reads names for these files, a few at a time, and remembers them.
    func readNames(of files: [URL]) async {
        guard !files.isEmpty, !unavailable else { return }
        // A few at a time: enough to feel quick, few enough not to send a whole Downloads folder at once.
        for batch in stride(from: 0, to: files.count, by: 4).map({ Array(files[$0..<min($0 + 4, files.count)]) }) {
            await withTaskGroup(of: (String, String?).self) { group in
                for file in batch {
                    group.addTask { (Self.key(file), await Self.readName(of: file)) }
                }
                for await (key, name) in group {
                    if let name { names[key] = name } else { unavailable = true }
                }
            }
            if unavailable { break }
        }
        if names.count > 1000 { names = names.filter { FileManager.default.fileExists(atPath: String($0.key.split(separator: "|")[0])) } }
        LampStore.save(names, to: "contentNames")
    }

    /// The name for one file: "" when there's nothing in it to go by, nil when the AI couldn't answer.
    nonisolated private static func readName(of file: URL) async -> String? {
        let text = String(await LampText.read(file).prefix(4000))
        var images: [NSImage] = []
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard FileKind.of(file) == .screenshot || FileKind.of(file) == .image,
                  let image = NSImage(contentsOf: file) else { return "" }
            images = [image]
        }
        struct Answer: Decodable { let name: String }
        let prompt = """
        Suggest a file name for this file, from what's in it: 2 to 6 words, in the language of its contents, \
        saying what it is and whose or what it's about (for example "Boarding pass Lisbon" or "Electricity bill \
        March"). No dates unless they're the point, no file extension, no punctuation. Answer as JSON: {"name": "…"}
        """
        do {
            let answer = try await LampAI.ask(prompt, data: images.isEmpty ? text : nil, images: images, as: Answer.self)
            return clean(answer.name)
        } catch {
            print("Tidy Up: couldn't name \(file.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// A name safe for Finder: no slashes or colons, no leading dot, not too long.
    nonisolated static func clean(_ name: String) -> String {
        var cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        return String(cleaned.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    nonisolated static func key(_ file: URL) -> String {
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return "\(file.path)|\(modified?.timeIntervalSince1970 ?? 0)"
    }
}
