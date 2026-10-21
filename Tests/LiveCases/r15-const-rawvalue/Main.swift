import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want constant=y like fresh=y, or a reopen):", show())
}}}
