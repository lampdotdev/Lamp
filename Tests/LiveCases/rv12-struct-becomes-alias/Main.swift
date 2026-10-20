import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let w = Wallet(); print("before:", show(w))
    reload(1); print("after1 (want amount=5 label=cash; or a reopen):", show(w))
}}}
