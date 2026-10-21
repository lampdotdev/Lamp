import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want constant=7 like fresh=7, or a reopen):", show())
}}}
