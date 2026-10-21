import Foundation
import SwiftData
@main struct Main { static func main() { MainActor.assumeIsolated {
    let container = try! ModelContainer(for: Note.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let n = Note(title: "abc"); container.mainContext.insert(n)
    print("before:", n.label)
    reload(1); print("after1 (the model reads a constant the change gives a new value, beside an unrelated new function: want a reopen):", n.label)
}}}
