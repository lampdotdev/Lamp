import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", Foo.sealed())
    reload(1); print("after:", Foo.sealed())
}}}
