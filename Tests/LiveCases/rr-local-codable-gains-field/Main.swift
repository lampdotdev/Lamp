import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Shelf(); print("before:", s.surprise())
    reload(1); print("after1 (want a reopen naming Answer inside Shelf.surprise(): it has to keep the new field to decode it):", s.surprise())
}}}
