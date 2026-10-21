import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let v = make(); print("before:", read(v))
    reload(1); print("after1 (want \"2 c\"):", read(v))
}}}
