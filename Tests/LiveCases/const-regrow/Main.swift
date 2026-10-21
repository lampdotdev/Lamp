import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want 3 3):", show())
    reload(2); print("after2 (want 4 4):", show())
}}}
