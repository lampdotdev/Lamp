import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want \"[[a, b]] [\"x\": [a]] c\", in place):", show())
}}}
