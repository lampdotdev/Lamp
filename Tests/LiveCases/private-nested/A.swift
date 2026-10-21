import Foundation
struct V {
    private struct Row { var n: Int }
    static func make() -> Any { Row(n: 1) }
    static func check(_ x: Any) -> Bool { x is Row }
}
