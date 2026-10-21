import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let n = N(); print("before:", use(n))
    reload(1); print("after (want A1b):", use(n))
}}}
