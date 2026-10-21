import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", describe())
    reload(1)
    print("after:", describe())
}}}
