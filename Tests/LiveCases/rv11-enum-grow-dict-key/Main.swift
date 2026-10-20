import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    bump(); print("before:", show())
    reload(1); bump(); print("after1 (want a:1 b:1 c:1 and lookups right):", show())
}}}
