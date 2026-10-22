import SwiftUI
struct ContentView: View {
    @Environment(Store.self) private var store
    var body: some View {
        let _ = Log.add("header=Shopping")
        VStack(spacing: Theme.spacing) {
            Text("Shopping").font(.headline)
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
