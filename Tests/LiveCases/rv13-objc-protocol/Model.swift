import Foundation
protocol Delegate: AnyObject { func ping() -> String }
final class Holder {
    weak var delegate: (any Delegate)?
    var n = 7
    func show() -> String { "n=\(n == 7 ? "7" : "not 7") ping=\(delegate?.ping() ?? "none")" }
}
final class Answerer: NSObject, Delegate { func ping() -> String { "pong" } }
