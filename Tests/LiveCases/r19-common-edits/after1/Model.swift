import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct Item: Identifiable, Hashable {
    let id: Int
    var title: String
    var done = false
}
enum Filter: String, CaseIterable, Identifiable {
    case all, open, done
    var id: String { rawValue }
}
enum Style {
    static let rowPadding: CGFloat = 4
}
@Observable final class Store {
    var items: [Item] = [Item(id: 1, title: "Milk"), Item(id: 2, title: "Eggs", done: true)]
    func toggle(_ item: Item) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].done.toggle() }
    }
    func clearDone() { items.removeAll(where: \.done) }
    func visible(_ filter: Filter) -> [Item] {
        switch filter {
        case .all: return items
        case .open: return items.filter { !$0.done }
        case .done: return items.filter(\.done)
        }
    }
}
struct ContentView: View {
    @State private var store = Store()
    var body: some View {
        ListView(store: store)
    }
}
struct ListView: View {
    let store: Store
    @State private var filter: Filter = .all
    var body: some View {
        let _ = Log.add("v1 list filter=\(filter.rawValue) cases=\(Filter.allCases.count)")
        VStack {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            Button("Clear Done") { store.clearDone() }
            ForEach(store.visible(filter)) { item in
                Row(item: item).onTapGesture { store.toggle(item) }
            }
        }
    }
}
struct Row: View {
    let item: Item
    var body: some View {
        let _ = Log.add("row \(item.title) done=\(item.done) pad=\(Style.rowPadding)")
        Text(item.title).padding(Style.rowPadding)
    }
}
