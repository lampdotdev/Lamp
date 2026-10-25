import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want a reopen: Color4 is held, by an inferred field, in a private struct read as bytes):", show())
}}}
