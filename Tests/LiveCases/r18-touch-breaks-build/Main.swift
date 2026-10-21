import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want <body>milk</body> before and after: the app's own code, valid Swift, must build live):", show())
}}}
