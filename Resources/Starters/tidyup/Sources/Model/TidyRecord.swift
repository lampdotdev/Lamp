import Foundation

/// One tidy, as the activity log shows it and as Undo takes it back: every file it moved, from where to where.
struct TidyRecord: Codable, Identifiable {
    struct Move: Codable, Hashable {
        var from: String
        /// Where the file went; for a file put in the Trash, its place in the Trash, so Undo can bring it back.
        var to: String
        var trashed = false
    }

    var id = UUID()
    var date = Date()
    var folderPath: String
    var moves: [Move]
    var automatic = false
    var undone = false
    /// Part of the sample content: shown with an Example tag, never undone, removed by Clear Examples.
    var isExample = false
}
