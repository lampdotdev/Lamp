import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Store(); print("before:", report(s))
    reload(1); print("after1 (want reopen; a reload reads a witness slot the app's table doesn't have):", report(s))
}}}
