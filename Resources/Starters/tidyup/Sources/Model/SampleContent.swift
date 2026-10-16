import Foundation

/// What a new person finds: Downloads and Desktop with sensible rules (nothing moves until they choose to),
/// and one activity entry marked as an example, so the log shows what a tidy looks like. Written once, on the
/// first launch; Clear Examples removes the entry, and it never comes back.
enum SampleContent {
    static func addIfFirstLaunch() {
        guard LampStore.load(Bool.self, from: "samplesAdded") == nil else { return }
        LampStore.save([WatchedFolder.downloads, WatchedFolder.desktop], to: "folders")
        LampStore.collection("tidies", of: TidyRecord.self).put(exampleTidy)
        LampStore.save(true, to: "samplesAdded")
    }

    /// A tidy of Downloads from yesterday morning, with made-up files.
    private static var exampleTidy: TidyRecord {
        let downloads = LampFolders.downloads.path
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) ?? Date()
        let date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: yesterday) ?? yesterday
        func move(_ name: String, to folder: String) -> TidyRecord.Move {
            .init(from: "\(downloads)/\(name)", to: "\(downloads)/\(folder)/\(name)")
        }
        return TidyRecord(date: date, folderPath: downloads, moves: [
            move("Electricity bill September.pdf", to: "Documents"),
            move("Lisbon trip photos.zip", to: "Archives"),
            move("IMG_2041.heic", to: "Images"),
            .init(from: "\(downloads)/Zoom installer.pkg", to: "", trashed: true),
        ], isExample: true)
    }
}
