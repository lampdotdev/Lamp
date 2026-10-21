import Foundation
final class Doc { var title = ""; var pages = 0; init() {}; convenience init(named: String) { self.init(); title = named; pages = 1 } }
func show(_ d: Doc) -> String { "\(d.title) \(d.pages)" }
