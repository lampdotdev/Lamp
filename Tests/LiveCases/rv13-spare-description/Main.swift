import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before (want Item(n: 1) and Pair<Int>(a: 5, b: Item(n: 1)), no field of Lamp's):", Shop.describe())
    reload(1); print("after1 (want badge: 3 shown where it was set, and no field of Lamp's):", Shop.describe())
}}}
