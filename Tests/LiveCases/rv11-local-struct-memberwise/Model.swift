import Foundation
final class Shelf {
    func pick() -> String {
        struct Answer { var dish: String }
        let a = Answer(dish: "rice")
        return a.dish
    }
}
