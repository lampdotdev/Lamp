import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Mood.b; print("before:", show(m))
    reload(1); print("after1 (want \"b b c c\"):", show(m))
}}}
