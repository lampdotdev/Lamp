import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    // Boxed before the change, as a framework keeps a value it was handed (a navigation path, a selection, a tag).
    let one: Any = Mood.sad, list: Any = [Mood.sad], key = AnyHashable(Mood.sad)
    print("before:", check(one), check(list), check(key))
    reload(1); print("after1 (want sad [sad] sad, as before):", check(one), check(list), check(key))
}}}
