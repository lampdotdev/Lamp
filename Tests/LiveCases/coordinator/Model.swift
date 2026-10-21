import AppKit
class Coordinator: NSObject {
    var log = ""
    @objc func tap(_ sender: Any?) { log = "tap-old" }
    func compute() -> Int { 1 }
}
final class FinalCoordinator: NSObject {
    var log = ""
    @objc func tap(_ sender: Any?) { log = "ftap-old" }
    func compute() -> Int { 10 }
}
