import Foundation
final class Box { var tags: Array<String> = ["a"]; var note: Optional<String> = nil; var size: (width: Int, height: Int) = (1, 2)
    func describe() -> String { "tags=\(tags.count) labels=done" } }
