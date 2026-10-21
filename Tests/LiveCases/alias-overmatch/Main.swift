import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let h = Holder(); print("before:", h.moods, h.ints.top ?? -1)
    reload(1)
    print("after:", h.moods, h.ints.top ?? -1)
}}}
