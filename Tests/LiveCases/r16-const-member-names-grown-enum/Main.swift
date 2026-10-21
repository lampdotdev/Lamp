import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want constant=3 like fresh=3, or a reopen):", show())
}}}
