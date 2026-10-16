import Foundation

/// A folder Tidy Up looks after, with its own rules.
struct WatchedFolder: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var path: String
    var rules = FolderRules()

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { FileManager.default.displayName(atPath: path) }

    var symbol: String {
        switch url.standardizedFileURL {
        case LampFolders.downloads.standardizedFileURL: return "arrow.down.circle"
        case LampFolders.desktop.standardizedFileURL: return "menubar.dock.rectangle"
        case LampFolders.documents.standardizedFileURL: return "doc"
        default: return "folder"
        }
    }

    static func == (a: WatchedFolder, b: WatchedFolder) -> Bool { a.id == b.id && a.path == b.path && a.rules == b.rules }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension WatchedFolder {
    /// Downloads: grouped by kind, and installers nobody has opened in a month go to the Trash.
    static var downloads: WatchedFolder {
        var rules = FolderRules()
        rules.group = GroupRule(mode: .byKind)
        rules.old = OldFilesRule(action: .trash, days: 30, scope: .installer)
        return WatchedFolder(path: LampFolders.downloads.path, rules: rules)
    }

    /// Desktop: screenshots named by what's in them and filed by month; everything else stays put.
    static var desktop: WatchedFolder {
        var rules = FolderRules()
        rules.rename = RenameRule(mode: .byContent, scope: .screenshot)
        rules.group = GroupRule(mode: .byMonth, scope: .screenshot)
        return WatchedFolder(path: LampFolders.desktop.path, rules: rules)
    }
}
