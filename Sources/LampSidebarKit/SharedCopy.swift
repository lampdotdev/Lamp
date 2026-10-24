import Foundation

/// The file the chat hands to the share menu (`SidebarSharing`), kept where the service it's shared with reads it.
/// This process can't reach the lasting file Lamp's own Share… hands on (`Store.sharedFile`), so it keeps one of
/// its own the same way: one file, in its own caches folder, which belongs to this one app's chat.
public enum SharedCopy {
    public static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Shared", isDirectory: true)
    }

    /// Writes the file Lamp sent where the one shared before was, and returns where it is. A service may still be
    /// reading the earlier file (an upload, a mail being written), so it's never removed first: the new file is
    /// put whole beside it and takes its place in one step, and whatever was handed the old one finds a file there
    /// at every moment.
    public static func keep(_ sharing: SidebarSharing, in folder: URL = folder) throws -> URL {
        let fm = FileManager.default
        let name = (sharing.file.name as NSString).lastPathComponent
        let file = folder.appendingPathComponent(name.isEmpty ? "Wish.lampapp" : name)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let nearby = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: file, create: true)
        defer { try? fm.removeItem(at: nearby) }
        let staged = nearby.appendingPathComponent(file.lastPathComponent)
        try sharing.file.data.write(to: staged)
        if fm.fileExists(atPath: file.path) {
            _ = try fm.replaceItemAt(file, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: file)
        }
        // Anything else here is the app's file under a name it no longer has.
        for old in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where old != file.lastPathComponent {
            try? fm.removeItem(at: folder.appendingPathComponent(old))
        }
        return file
    }

    /// The folders a chat from before kept its shared files in, one for each share in the temporary folder. Left an
    /// hour, so a file one of them handed on just before the chat was updated is read by then.
    public static func removeEarlierFolders() {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory
        for old in (try? fm.contentsOfDirectory(atPath: temporary.path)) ?? [] where old.hasPrefix("share-") {
            let folder = temporary.appendingPathComponent(old)
            guard let made = (try? fm.attributesOfItem(atPath: folder.path))?[.modificationDate] as? Date,
                  made < Date().addingTimeInterval(-3600) else { continue }
            try? fm.removeItem(at: folder)
        }
    }
}
