import AppKit
class Coordinator: NSObject {
    var log = ""
    @objc func tap(_ sender: Any?) { log = "tap-NEW2 " + extra() }
    func compute() -> Int { 3 }
    func extra() -> String { "extra" }
}
final class FinalCoordinator: NSObject {
    var log = ""
    @objc func tap(_ sender: Any?) { log = "ftap-NEW2 " + extra() }
    func compute() -> Int { 30 }
    func extra() -> String { "fextra" }
}
