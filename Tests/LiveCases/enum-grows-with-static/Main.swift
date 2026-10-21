import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    bump(); bump(); remember(); print("before:", show())
    reload(1); print("after1 (want \"2 c same\"):", show())
    bump(); print("after1 bumped (want \"3 c same\"):", show())
}}}
