import Foundation
struct Note { var title = "a"; var starred = false }
func star(_ n: inout Note) { n.starred = true }
func show(_ n: Note) -> String { "\(n.title) starred=\(n.starred)" }
