import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", Foo.s())
    reload(1); print("after:", Foo.s())
}}}
