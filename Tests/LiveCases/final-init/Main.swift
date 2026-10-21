import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let e = Engine(); print("before:", e.name)
    reload(1)
    print("after:", e.name, make().name)
}}}
