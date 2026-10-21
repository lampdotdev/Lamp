import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", Shapes.describe())
    reload(1); print("after1 (want \"0 9 shape SQUARE\", each method's new code):", Shapes.describe())
}}}
