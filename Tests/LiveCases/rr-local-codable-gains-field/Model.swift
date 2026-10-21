import Foundation
final class Shelf {
    func choose() -> String {
        struct Answer: Decodable { let id: String }
        return (try? JSONDecoder().decode(Answer.self, from: Data(#"{"id":"a"}"#.utf8)))?.id ?? "?"
    }
    func surprise() -> String {
        struct Answer: Decodable { let why: String }
        return (try? JSONDecoder().decode(Answer.self, from: Data(#"{"why":"w","dish":"d"}"#.utf8)))?.why ?? "?"
    }
}
