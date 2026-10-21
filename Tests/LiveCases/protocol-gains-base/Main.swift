import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Store(); print("before:", total(s))
    reload(1); print("after1 (want reopen; a reload calls area through a table laid out without the base):", total(s))
}}}
