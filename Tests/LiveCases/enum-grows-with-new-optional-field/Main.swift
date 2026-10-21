import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var i = Item(); print("before:", show(i))
    reload(1); print("after1 (want \"1 none\" then \"1 c\"):", show(i), { pick(&i); return show(i) }())
    reload(2); print("after2 (reopen expected: the spare holds Mood):", show(i))
}}}
