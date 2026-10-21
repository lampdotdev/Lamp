import Foundation
@main // the entry, with a note after it as some apps write it
struct Main { static func main() { MainActor.assumeIsolated {
    let list: any Describable = [Item()]
    print("before:", show(list))
    reload(1); print("after1 (want array: the Array now answers describe() itself):", show(list))
}}}
