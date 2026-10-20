import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var item = Item(id: 1, title: "a")
    print("before:", describe(item), json(item))
    reload(1)
    poke(&item)
    print("after:", describe(item), json(item))
}}}
