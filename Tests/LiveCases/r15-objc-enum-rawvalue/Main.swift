import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let gauge = Gauge(); print("before:", gauge.describe())
    reload(1); print("after1 (want level=low, or a reopen: an @objc enum's value is its raw value):", gauge.describe())
}}}
