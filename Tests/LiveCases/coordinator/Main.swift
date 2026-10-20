import Foundation
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    let c = Coordinator(), f = FinalCoordinator()
    func fire() -> String { "\(c.perform(NSSelectorFromString("tap:"), with: nil).map { _ in "" } ?? "") \(c.log) | \(f.perform(NSSelectorFromString("tap:"), with: nil).map { _ in "" } ?? "")\(f.log) | direct: \(c.compute()) \(f.compute())" }
    print("before:", fire())
    reload(1); print("after1 (bodies changed):", fire())
    reload(2); print("after2 (methods added):", fire())
}}}
