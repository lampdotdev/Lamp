import Foundation
final class Doc { var title: String; init(title: String) { self.title = title } }
func make() -> Doc { Doc(title: "a") }
