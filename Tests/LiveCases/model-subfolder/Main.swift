import Foundation
import SwiftData
@main struct Main { static func main() { MainActor.assumeIsolated {
    let container = try! ModelContainer(for: Note.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let n = Note(title: "abc"); container.mainContext.insert(n)
    print("before:", label(n))
    reload(1); print("after1 (want LABEL):", label(n))
    reload(2); print("after2 (should have reopened):", label(n))
}}}
