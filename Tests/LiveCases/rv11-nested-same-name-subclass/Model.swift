import Foundation
enum A {
    class Item { var x = 1 }
}
enum B {
    class Item: A.Item { var y = 2 }
}
func show() -> String { "\(B.Item().x + B.Item().y)" }
