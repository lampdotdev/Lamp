import AppKit
class Coordinator: NSObject {
    var log = ""
    @objc func tap(_ sender: Any?) { log = "tap-NEW" }
    func compute() -> Int { 2 }
}
final class FinalCoordinator: NSObject {
    var log = ""
    @objc func tap(_ sender: Any?) { log = "ftap-NEW" }
    func compute() -> Int { 20 }
}
