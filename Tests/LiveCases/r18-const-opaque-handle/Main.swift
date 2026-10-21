import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want a reopen: the handle was opened once, and a new one would leave the open app's first behind):", show())
}}}
