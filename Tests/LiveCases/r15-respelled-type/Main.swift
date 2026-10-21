import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let box = Box(); print("before:", box.describe())
    reload(1); print("after1 (want live: the same types, spelt another way; labels=done):", box.describe())
}}}
