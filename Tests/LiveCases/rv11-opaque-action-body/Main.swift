import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", describe())
    reload(1); print("after1 (want v1 in place: the action's body is code, not the type):", describe())
}}}
