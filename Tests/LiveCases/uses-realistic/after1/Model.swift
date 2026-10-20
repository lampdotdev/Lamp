import SwiftUI
enum Tab: String, CaseIterable { case home, settings, about }
struct Item: Identifiable { let id = UUID(); var name: String; var done = false }
@Observable final class Model {
    var tab: Tab = .home
    var items: [Item] = [Item(name: "a")]
    var ticks = 0
    var title: String { switch tab { case .home: "Home"; case .settings: "Settings"; case .about: "About" } }
    private var timer: Timer?
    // As the liveNote asks: the timer calls a method each time rather than doing the work in the closure.
    func start() { timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in self?.tick() } }
    func stop() { timer?.invalidate() }
    func tick() { ticks += 1 }
    func load() async { try? await Task.sleep(for: .milliseconds(5)); items.append(Item(name: "b")) }
    func save() async { ticks += 100 }
    func describe() -> String { "tab=\(tab) title=\(title) cases=\(Tab.allCases.count) ticking=\(ticks > 0) items=\(items.count)" }
}
struct ContentView: View {
    @Bindable var model: Model
    var body: some View {
        VStack {
            Text(model.title)
            Picker("Tab", selection: $model.tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) } }
            Button("Save") { Task { await model.save() } }
            List(model.items) { Text($0.name) }
        }
        .task { await model.load() }
        .onChange(of: model.tab) { _, new in print(new) }
    }
}
