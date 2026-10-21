import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want constant=7 like fresh=7 and level=2 like fresh=2, or a reopen):", show())
}}}
