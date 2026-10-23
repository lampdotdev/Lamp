import SwiftUI
struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var showDone = false
    var body: some View {
        let _ = Log.add("header=Shopping showDone=\(showDone)")
        VStack(spacing: Theme.spacing) {
            Text("Shopping").font(.headline)
            Summary(count: store.items.count)
            ForEach(store.items) { item in ItemRow(item: item, isFirst: item.id == store.items.first?.id) }
        }
    }
}
struct ItemRow: View {
    let item: Item
    let isFirst: Bool
    var body: some View {
        let _ = Log.add("row \(item.name) first=\(isFirst)")
        Text(item.name)
    }
}
struct Summary: View {
    let count: Int
    var body: some View {
        let _ = Log.add("summary \(count) items")
        Text("\(count) items").foregroundStyle(.secondary)
    }
}
