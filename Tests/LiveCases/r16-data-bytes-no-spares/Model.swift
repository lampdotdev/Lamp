import Foundation
struct Note { var title = "a" }
func star(_ n: inout Note) {}
func show(_ n: Note) -> String { n.title }
