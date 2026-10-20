import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", report())
    reload(1); print("after1 (want 3.0 / 6.0 / big):", report())
    reload(2); print("after2 (reopen expected: Settings holds an object):", report())
}}}
