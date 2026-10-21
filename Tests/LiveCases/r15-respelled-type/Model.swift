import Foundation
final class Box { var tags: [String] = ["a"]; var note: String? = nil; var size: (width: Int, height: Int) = (1, 2)
    func describe() -> String { "tags=\(tags.count)" } }
