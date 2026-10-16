import Foundation

/// A folder's rules: what happens to names, where files are grouped, what happens to old files, and what is
/// never touched. Each is shown as one sentence the person edits (RulesView). Every rule has a scope, nil for
/// all files or one kind ("Name screenshots by what's in them").
struct FolderRules: Codable, Equatable {
    var rename = RenameRule()
    var group = GroupRule()
    var old = OldFilesRule()
    /// What's never touched: ".psd" means an extension, anything else a word in the name (case doesn't matter).
    var skip: [String] = []
    var auto: AutoTidy = .off
}

struct RenameRule: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable {
        case keep, dateFirst, byContent
    }
    var mode: Mode = .keep
    var scope: FileKind? = nil
}

struct GroupRule: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable {
        case none, byKind, byMonth
    }
    var mode: Mode = .none
    var scope: FileKind? = nil
}

struct OldFilesRule: Codable, Equatable {
    enum Action: String, Codable, CaseIterable {
        case leave, archive, trash
    }
    var action: Action = .leave
    var days = 30
    var scope: FileKind? = nil
}

/// When the folder is tidied without anyone clicking Tidy Now. Off to begin with: a new person sees what
/// would happen before anything moves.
enum AutoTidy: String, Codable, CaseIterable {
    case off, whenFilesArrive, daily
}

extension FolderRules {
    /// Whether a file matches the skip list.
    func skips(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        return skip.contains { entry in
            let entry = entry.trimmingCharacters(in: .whitespaces).lowercased()
            guard !entry.isEmpty else { return false }
            return entry.hasPrefix(".") ? ext == String(entry.dropFirst()) : name.contains(entry)
        }
    }
}
