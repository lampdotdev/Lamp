import Foundation
final class Doc { var title = ""; init() {}; convenience init(named: String) { self.init(); title = named } }
func show(_ d: Doc) -> String { d.title }
