import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want in, as for the same enum nested in a type whose name shares no word with it):", show())
}}}
