import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", table())
    reload(1); print("after1 (the maintainer must decide what is wanted; now):", table(), "fresh:", build())
}}}
