import Foundation

/// Carries out a plan and takes one back. Every file is moved, never copied over or deleted: a name already
/// taken gets " 2", and "delete" means the Trash, where the person can still find it.
enum Mover {
    /// Moves each planned file and returns what was actually done. A file that changed since the preview
    /// (gone, or just written to) is left alone.
    static func apply(_ changes: [PlannedChange], rules: FolderRules) -> [TidyRecord.Move] {
        let fm = FileManager.default
        var moves: [TidyRecord.Move] = []
        var taken = Set<String>()
        for change in changes where !change.waitingForName {
            let source = change.source
            guard fm.fileExists(atPath: source.path), Planner.isSafe(source, rules: rules, now: Date()) else { continue }
            do {
                if let destination = change.destination {
                    // Checked again now: something may have taken the name since the preview.
                    let target = Planner.uniqueURL(destination, taken: &taken)
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: source, to: target)
                    moves.append(.init(from: source.path, to: target.path))
                } else {
                    var inTrash: NSURL?
                    try fm.trashItem(at: source, resultingItemURL: &inTrash)
                    moves.append(.init(from: source.path, to: (inTrash as URL?)?.path ?? "", trashed: true))
                }
            } catch {
                print("Tidy Up: couldn't move \(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return moves
    }

    /// Puts every file of a tidy back where it was, last first. A file the person has moved or emptied from the
    /// Trash since stays where it is; one whose old name is taken again comes back as " 2". Returns how many
    /// came back.
    static func undo(_ record: TidyRecord) -> Int {
        let fm = FileManager.default
        var restored = 0
        var taken = Set<String>()
        var emptied = Set<URL>()
        for move in record.moves.reversed() {
            let current = URL(fileURLWithPath: move.to)
            guard !move.to.isEmpty, fm.fileExists(atPath: current.path) else { continue }
            let original = Planner.uniqueURL(URL(fileURLWithPath: move.from), taken: &taken)
            do {
                try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: current, to: original)
                restored += 1
                if !move.trashed { emptied.insert(current.deletingLastPathComponent()) }
            } catch {
                print("Tidy Up: couldn't put back \(current.lastPathComponent): \(error.localizedDescription)")
            }
        }
        // Folders the tidy made inside the watched folder and that are empty again go too; one holding anything
        // at all stays, and so does the watched folder itself.
        let inside = emptied.filter { $0.path.hasPrefix(record.folderPath + "/") }
        for folder in inside where (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? fm.removeItem(at: folder)
        }
        return restored
    }
}
