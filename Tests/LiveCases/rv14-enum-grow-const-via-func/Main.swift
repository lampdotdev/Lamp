import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want direct=3 viaFunc=3, both constants made from the grown enum):", show())
    reload(2); print("after2 (want direct=4 viaFunc=4, grown again):", show())
}}}
