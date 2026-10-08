import Foundation

/// A shared app opened before setup finished. Lamp keeps a copy and remembers it on disk, like the requests
/// waiting for setup, so its review opens by itself once setup is done, in this run or the next.
struct WaitingImport {
    static let key = "waitingSharedApp"
    var defaults = UserDefaults.standard
    /// Where files waiting for setup are kept, each in a folder of its own.
    let folder: URL

    /// Keeps a copy, since the file may be a temporary one (opened straight from Mail or Messages).
    /// The newest one wins, as it does for the review: an earlier copy goes. False when no copy could be
    /// made (a full disk, say): nothing is remembered then, so Lamp never promises a file it may not have.
    func keep(_ file: URL) -> Bool {
        let fm = FileManager.default
        let home = folder.appendingPathComponent(UUID().uuidString)
        let copy = home.appendingPathComponent(file.lastPathComponent)
        do {
            try fm.createDirectory(at: home, withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: copy)
        } catch {
            try? fm.removeItem(at: home)
            return false
        }
        discard()
        defaults.set(copy.path, forKey: Self.key)
        return true
    }

    /// Hands the kept file over, once: asking again gives nothing, so its review can't open twice.
    func take() -> URL? {
        guard let path = defaults.string(forKey: Self.key) else { return nil }
        defaults.removeObject(forKey: Self.key)
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    /// The folder holding the kept copy, which clearing out old waiting files must leave alone. Only ever
    /// a folder inside this one, whatever the saved setting says: it is also what an earlier copy's removal goes by.
    var keptFolder: String? {
        guard let path = defaults.string(forKey: Self.key) else { return nil }
        let home = URL(fileURLWithPath: path).deletingLastPathComponent()
        return home.deletingLastPathComponent().path == folder.path ? home.path : nil
    }

    private func discard() {
        if let keptFolder { try? FileManager.default.removeItem(atPath: keptFolder) }
        defaults.removeObject(forKey: Self.key)
    }
}
