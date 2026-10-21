import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let h = Holder(); print("before:", h.tally)
    reload(1)
    print("after:", h.tally)
}}}
