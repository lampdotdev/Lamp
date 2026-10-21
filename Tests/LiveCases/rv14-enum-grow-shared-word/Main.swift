import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want in, as for an enum named Mood: the app here is named Case, and its enum CaseStatus shares the word):", show())
}}}
