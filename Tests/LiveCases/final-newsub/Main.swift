import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", describe())
    reload(1); print("after1:", describe())
    reload(2); print("after2:", describe())
}}}
