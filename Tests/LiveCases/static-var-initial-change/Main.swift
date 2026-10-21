import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (the app read it already: 1 is right; the new 5 can't apply):", show())
    reload(2); print("after2 (never read before: should it be 9?):", late())
}}}
