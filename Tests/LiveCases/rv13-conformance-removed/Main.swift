import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want \"Item(n: 1) plain\", the conformances are gone):", show())
}}}
