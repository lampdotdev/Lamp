import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    let s = Shelf()
    print("before:", s.tonight("rice"))
    reload(1)
    print("after1 (want in place: \"rice 2 surprise\"):", s.tonight("rice"), s.surprise())
}}}
