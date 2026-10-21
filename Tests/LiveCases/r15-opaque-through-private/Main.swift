import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", describe())
    reload(1); print("after1 (want 'a longer label than before', or a reopen):", describe())
    print("again:", describe())
}}}
