import Foundation
final class Shelf {
    func pick() -> String {
        struct Answer { var dish: String; var spicy = false }
        let a = Answer(dish: "rice", spicy: true)
        return "\(a.dish) \(a.spicy)"
    }
}
