import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Store(); print("before:", show(s))
    reload(1); bump(s); print("after1 (want reopen; a reload here reads structs as objects):", show(s))
}}}
