import SwiftUI
struct ContentView: View {
    @Environment(Store.self) private var store
    var body: some View {
        let _ = Log.add("header=Groceries")
        VStack(spacing: Theme.spacing) {
            Text("Groceries").font(.headline)
            ForEach(store.items) { item in ItemRow(item: item) }
        }
    }
}
struct ItemRow: View {
    let item: Item
    var body: some View {
        let _ = Log.add("row \(item.name)")
        Text(item.name)
    }
}
