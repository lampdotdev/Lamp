import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want shelves=3 everywhere, like live, or a reopen: a theme with a font field lists the cases of an enum that grew):", show())
}}}
