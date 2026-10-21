import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", Reader.speed())
    reload(1); print("after1 (want 10):", Reader.speed())
    reload(2); print("after2 (want 10, now a var the app can change, or a reopen):", Reader.speed())
}}}
