import SwiftUI
import Combine
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.joined(separator: ", ") }
}
enum Hook { @MainActor static var tap: (() -> Void)? }
@Observable final class Model { var count = 0 }
final class Legacy: ObservableObject { @Published var count = 0 }
struct Panel: View {
    var model: Model
    @ObservedObject var legacy: Legacy
    var body: some View {
        let _ = Log.add("count=\(model.count) legacy=\(legacy.count)")
        Text("x")
    }
}
@MainActor func poke(_ model: Model, _ legacy: Legacy) {}
