import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let holder = Holder(); print("before:", holder.show())
    reload(1); print("after1 (want a reopen: upload<T> hands any array over as bytes, which Lamp can't follow):", holder.show())
}}}
