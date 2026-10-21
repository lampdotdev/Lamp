import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", Reader.show(Item(), Box()))
    reload(1); print("after1 (want \"stored stored\", what the new code means):", Reader.show(Item(), Box()))
}}}
