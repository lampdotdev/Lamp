import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want \"none 1\"):", show())
    reload(2); print("after2 (want \"7 1\"):", show())
}}}
