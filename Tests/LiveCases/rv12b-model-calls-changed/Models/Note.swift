import SwiftData
@Model final class Note {
    var title: String
    init(title: String) { self.title = title }
    var label: String { shout(title) }
}
