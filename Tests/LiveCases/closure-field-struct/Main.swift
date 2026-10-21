import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let b = Item(title: "x", action: { print("ran") }); print("before:", show(b))
    reload(1); print("after1 (want \"x 0\" then \"y 2\"):", show(b), show(made()))
}}}
