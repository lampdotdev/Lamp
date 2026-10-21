import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want the open app's settings kept as they were made, volume=5: a stored var is state, as an object's fields are):", show())
}}}
