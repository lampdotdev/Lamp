import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", half())
    reload(1); print("after1 (want 10, half the new width):", half())
    reload(2); print("after2 (want 15):", half())
}}}
