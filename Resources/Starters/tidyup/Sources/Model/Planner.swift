import Foundation

/// One file the rules would change: where it is and where it would go.
struct PlannedChange: Identifiable, Hashable {
    var id: String { source.path }
    let source: URL
    /// Where it goes; nil means the Trash.
    let destination: URL?
    /// Why, in a few words ("Grouped into Images", "Installer older than 30 days").
    let reason: String
    /// Its name is being read from its contents; it may still change.
    var waitingForName = false
}

/// Works out what a folder's rules would do, without touching anything. The preview shows its answer and
/// Tidy Now carries it out, so what the person saw is what happens.
///
/// Safety lives here: only files directly in the folder are looked at (never inside other folders, except
/// the old-files rule reaching into the folders Tidy Up groups into), nothing still downloading or changed in
/// the last minute, nothing on the skip list, and no name is ever given to two files.
enum Planner {
    struct Plan {
        var changes: [PlannedChange] = []
        /// The folder couldn't be read (macOS hasn't allowed it yet, or it's gone).
        var unreadable = false
        /// Files whose names are to be read from their contents and aren't yet.
        var unnamed: [URL] = []
    }

    /// Browsers and download tools write into these until the download is done.
    static let inProgressExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload", "tmp"]
    /// A file changed more recently than this may still be being written or saved.
    static let settleTime: TimeInterval = 60
    static let archiveFolderName = "Archive"
    /// How many files one tidy names by their contents.
    static let namingBatch = 12

    /// - Parameters:
    ///   - contentName: the name read from a file's contents, when it has been (ContentNamer); empty when the
    ///     file had nothing to go by.
    ///   - canName: whether names can be read now; when not, files keep their names rather than wait.
    static func plan(_ folder: WatchedFolder, contentName: (URL) -> String?, canName: Bool, now: Date = Date()) -> Plan {
        var plan = Plan()
        guard (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil else {
            plan.unreadable = true
            return plan
        }
        let rules = folder.rules
        var taken = Set<String>()
        var toName = 0

        for file in LampFolders.files(in: folder.url) where isSafe(file, rules: rules, now: now) {
            let kind = FileKind.of(file)
            var name = file.lastPathComponent
            var reasons: [String] = []
            var waiting = false

            if applies(rules.rename.scope, to: kind) {
                switch rules.rename.mode {
                case .keep:
                    break
                case .dateFirst where !startsWithDate(name):
                    name = dayFormatter.string(from: created(file)) + " " + name
                    reasons.append("Date first")
                case .byContent where looksGeneric(file):
                    // A few at a time, newest first, so a Desktop of two hundred screenshots isn't sent to the AI
                    // all at once: the rest stay where they are until a later tidy reaches them.
                    toName += 1
                    guard toName <= namingBatch || !canName else { continue }
                    // An empty name means the file was read and had nothing to name it by: it keeps its own.
                    let read = contentName(file)
                    if let read, !read.isEmpty {
                        name = read + (file.pathExtension.isEmpty ? "" : "." + file.pathExtension)
                        reasons.append("Named by what's in it")
                    } else if read == nil, canName {
                        waiting = true
                        plan.unnamed.append(file)
                    }
                default:
                    break
                }
            }

            var destination: URL? = folder.url.appendingPathComponent(name)
            if let oldReason = oldReason(file, kind: kind, rules: rules.old, now: now) {
                destination = rules.old.action == .trash ? nil
                    : folder.url.appendingPathComponent(archiveFolderName).appendingPathComponent(name)
                reasons.append(oldReason)
            } else if let group = groupFolder(for: file, kind: kind, rule: rules.group) {
                destination = folder.url.appendingPathComponent(group).appendingPathComponent(name)
                reasons.append("Grouped into \(group)")
            }

            if let target = destination, target.standardizedFileURL == file.standardizedFileURL {
                if waiting { plan.changes.append(PlannedChange(source: file, destination: file, reason: "Reading…", waitingForName: true)) }
                continue
            }
            let unique = destination.map { uniqueURL($0, taken: &taken) }
            plan.changes.append(PlannedChange(source: file, destination: unique, reason: reasons.joined(separator: " · "),
                                              waitingForName: waiting))
        }

        // Files Tidy Up grouped earlier are still reached by the old-files rule, or an installer grouped on its
        // first day would never be cleared out. Nothing else looks inside folders.
        if rules.old.action != .leave {
            for group in groupedFolders(in: folder.url) {
                for file in LampFolders.files(in: group) where isSafe(file, rules: rules, now: now) {
                    guard let reason = oldReason(file, kind: FileKind.of(file), rules: rules.old, now: now) else { continue }
                    let target = rules.old.action == .trash ? nil
                        : uniqueURL(folder.url.appendingPathComponent(archiveFolderName).appendingPathComponent(file.lastPathComponent), taken: &taken)
                    plan.changes.append(PlannedChange(source: file, destination: target, reason: reason))
                }
            }
        }
        return plan
    }

    // MARK: Safety

    static func isSafe(_ file: URL, rules: FolderRules, now: Date) -> Bool {
        if inProgressExtensions.contains(file.pathExtension.lowercased()) { return false }
        if file.lastPathComponent.hasPrefix(".") || rules.skips(file) { return false }
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        let latest = max(values?.contentModificationDate ?? .distantPast, values?.creationDate ?? .distantPast)
        return now.timeIntervalSince(latest) > settleTime
    }

    /// A free name for the file at `url`: the same name with " 2", " 3"… when one is already there or already
    /// promised to another file in this plan. Nothing is ever overwritten.
    static func uniqueURL(_ url: URL, taken: inout Set<String>) -> URL {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = url
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) || taken.contains(candidate.path.lowercased()) {
            let name = "\(base) \(number)" + (ext.isEmpty ? "" : ".\(ext)")
            candidate = folder.appendingPathComponent(name)
            number += 1
        }
        taken.insert(candidate.path.lowercased())
        return candidate
    }

    // MARK: Rules

    static func applies(_ scope: FileKind?, to kind: FileKind?) -> Bool {
        scope == nil || scope == kind
    }

    private static func oldReason(_ file: URL, kind: FileKind?, rules: OldFilesRule, now: Date) -> String? {
        guard rules.action != .leave, applies(rules.scope, to: kind) else { return nil }
        let age = now.timeIntervalSince(created(file)) / 86_400
        guard age > Double(rules.days) else { return nil }
        return "\(rules.scope?.singular ?? "File") older than \(rules.days) days"
    }

    private static func groupFolder(for file: URL, kind: FileKind?, rule: GroupRule) -> String? {
        guard applies(rule.scope, to: kind) else { return nil }
        let name: String?
        switch rule.mode {
        case .none: name = nil
        case .byKind: name = kind?.folderName
        case .byMonth: name = monthFormatter.string(from: created(file))
        }
        // A file already has the folder's name: leave this one where it is rather than fail to make the folder.
        var isFolder: ObjCBool = false
        if let name, FileManager.default.fileExists(atPath: file.deletingLastPathComponent().appendingPathComponent(name).path,
                                                    isDirectory: &isFolder), !isFolder.boolValue {
            return nil
        }
        return name
    }

    /// The folders Tidy Up groups into: one per kind, and one per month ("2026-10 October").
    private static func groupedFolders(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let kindFolders = Set(FileKind.allCases.map(\.folderName))
        return names.filter { kindFolders.contains($0) || $0.range(of: #"^\d{4}-\d{2} "#, options: .regularExpression) != nil }
            .map { folder.appendingPathComponent($0) }
    }

    /// When the file arrived: its creation date, which moving it doesn't change.
    static func created(_ file: URL) -> Date {
        let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? Date()
    }

    private static func startsWithDate(_ name: String) -> Bool {
        name.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
    }

    /// Names that say nothing about the file: those cameras, screenshot tools and browsers make up. Only these
    /// are named by their contents, so a name the person chose is never replaced.
    static func looksGeneric(_ file: URL) -> Bool {
        let base = file.deletingPathExtension().lastPathComponent.lowercased()
        let made = ["screenshot", "screen shot", "cleanshot", "scan", "img_", "img-", "dsc", "pxl_", "untitled",
                    "document", "image", "download", "file", "unnamed", "photo", "capture"]
        if made.contains(where: { base.hasPrefix($0) }) { return true }
        let letters = base.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return Double(letters) < Double(base.count) * 0.4
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// "2026-10 October": sorts by date in Finder and still reads as a month.
    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM LLLL"
        return formatter
    }()
}
