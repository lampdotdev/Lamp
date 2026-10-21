import Foundation
final class Doc { var title: String; init(title: String) { self.title = title }; convenience init() { self.init(title: "untitled") } }
func make() -> Doc { Doc() }
