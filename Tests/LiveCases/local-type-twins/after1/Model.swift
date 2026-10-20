import Foundation
struct Pick { var dish: String; var why: String; var surprise = false }
final class Shelf {
    var picks: [Pick] = []
    // A reply's shape, declared where it's read: another function may declare its own of the same name.
    func tonight(_ dish: String) -> String {
        struct Answer: Decodable { let dish: String; let why: String }
        let answer = try! JSONDecoder().decode(Answer.self, from: Data("{\"dish\":\"\(dish)\",\"why\":\"w\"}".utf8))
        picks.append(Pick(dish: answer.dish, why: answer.why))
        return "\(answer.dish) \(picks.count)"
    }
    func surprise() -> String {
        struct Answer: Decodable { let dish: String; let why: String; let jar: String }
        let answer = try! JSONDecoder().decode(Answer.self, from: Data("{\"dish\":\"d\",\"why\":\"w\",\"jar\":\"cumin\"}".utf8))
        picks.append(Pick(dish: answer.dish, why: answer.why, surprise: true))
        return picks.last!.surprise ? "surprise" : "plain"
    }
}
