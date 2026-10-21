import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", describe(Row(title: "t")))
    reload(1); print("after1 (want \"t bindings=1\" in place: a key path's \\.$count is the view's state's binding too):", describe(Row(title: "t")))
}}}
