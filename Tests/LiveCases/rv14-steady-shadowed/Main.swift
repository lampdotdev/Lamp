import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Style()
    print("before:", show(s))
    reload(1); print("after1 (the app's own Color makes a new value at each .blue: want a reopen, or the same tint read twice):", show(s))
}}}
