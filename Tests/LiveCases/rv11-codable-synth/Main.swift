import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var t = Todo(); print("before:", save(t))
    reload(1); mark(&t); print("after1 (want done true in the JSON and read back):", save(t), "|", readBack(save(t)))
}}}
