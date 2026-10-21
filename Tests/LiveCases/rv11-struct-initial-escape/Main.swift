import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let i = Item(); print("before:", show(i))
    reload(1); print("after1 (want in place: a string with an escape is a literal):", show(i))
    reload(2); print("after2 (want in place: 0xFF is a literal):", show(i))
}}}
