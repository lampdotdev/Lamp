import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", describe(Row(title: "t")))
    reload(1); print("after1 (want \"t open=true\" in place):", describe(Row(title: "t")))
}}}
