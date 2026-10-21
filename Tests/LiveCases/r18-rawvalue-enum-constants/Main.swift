import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want shelves=3 like live=3, as ranks=3, or a reopen; and open=2 only with a reopen: two enums gained a case, one with String raw values, one with Int raw values):", show())
    reload(2); print("after2 (want start=fridge, in place like any plain constant: a constant of the String enum changed):", show())
    reload(3); print("after3 (want size=14.0, in place: a theme constant holding that enum changed):", show())
}}}
