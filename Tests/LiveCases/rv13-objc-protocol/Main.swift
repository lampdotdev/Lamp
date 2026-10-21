import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let a = Answerer(), h = Holder()
    h.delegate = a
    print("before:", h.show())
    reload(1); print("after1 (want \"n=7 ping=pong\", or a reopen):", h.show())
    withExtendedLifetime(a) {}
}}}
