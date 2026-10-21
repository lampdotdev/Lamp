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
    var label: String { done ? "done: " + title : title }
}
enum Filter: String, CaseIterable, Identifiable {
    case all, open, done, starred
    var id: String { rawValue }
}
enum Style {
    static let rowPadding: CGFloat = 8
}
@Observable final class Store {
    var items: [Item] = [Item(id: 1, title: "Milk"), Item(id: 2, title: "Eggs", done: true)]
    func flip(_ item: Item) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].done.toggle() }
    }
    var clearedCount = 0
    func clearDone() { clearedCount += items.filter(\.done).count; items.removeAll(where: \.done) }
    func visible(_ filter: Filter) -> [Item] {
        switch filter {
        case .all: return items
        case .open: return items.filter { !$0.done }
        case .done: return items.filter(\.done)
        case .starred: return []
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
    @State private var showingInfo = false
    var body: some View {
        let _ = Log.add("v9 list info=\(showingInfo) cleared=\(store.clearedCount) filter=\(filter.rawValue) cases=\(Filter.allCases.count)")
        VStack {
            Header(count: store.items.count)
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            Button("Clear Done") { store.clearDone() }
            Button("Info") { showingInfo = true }
            ForEach(store.visible(filter)) { item in
                Row(item: item).onTapGesture { store.flip(item) }
            }
        }
        .sheet(isPresented: $showingInfo) { Text("Info") }
    }
}
struct Row: View {
    let item: Item
    var body: some View {
        let _ = Log.add("v8 row \(item.label) done=\(item.done) pad=\(Style.rowPadding)")
        Text(item.label).bold().padding(Style.rowPadding)
    }
}

struct Header: View {
    let count: Int
    var body: some View {
        let _ = Log.add("v6 header \(count)")
        Text("\(count) items")
    }
}
