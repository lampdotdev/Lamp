import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Store(); print("before:", s.show())
    reload(1); print("after1 (want cast=1 key=true, the values the store holds):", s.show())
}}}
