import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", Board.show())
    reload(1); print("after1 (want \"20 400\" as a fresh launch, or a reopen as for a new starting value):", Board.show())
}}}
