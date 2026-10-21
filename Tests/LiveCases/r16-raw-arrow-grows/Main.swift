import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want 3 cases, going in as any enum that only gained a case at the end):", show())
}}}
