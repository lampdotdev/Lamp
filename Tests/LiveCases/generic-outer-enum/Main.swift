import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let boxed: Any = Stack<Int>.Mode.b
    let s = Stack<Int>(); print("before:", unbox(boxed), show(s))
    reload(1); print("after1 (want \"mode b\" and the third case):", unbox(boxed), show(s))
}}}
