import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", describe())
    reload(1); print("after1 (want v1 in place: the type is the same ModifiedContent<Text, _PaddingLayout>):", describe())
}}}
