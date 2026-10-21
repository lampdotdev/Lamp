import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want count=2, Item in Shop now names Special):", show())
    reload(2); print("after2 (want count=1, the alias is gone again):", show())
}}}
