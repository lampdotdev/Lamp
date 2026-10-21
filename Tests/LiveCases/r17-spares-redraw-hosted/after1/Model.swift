import SwiftUI
import Combine
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.joined(separator: ", ") }
}
enum Hook { @MainActor static var tap: (() -> Void)? }
@Observable final class Model { var count = 0; var stars = 0 }
final class Legacy: ObservableObject { @Published var count = 0; @Published var stars = 0 }
struct Panel: View {
    var model: Model
    @ObservedObject var legacy: Legacy
    @State private var taps = 0
    var body: some View {
        let _ = Log.add("stars=\(model.stars) legacy=\(legacy.stars) taps=\(taps)")
        let _ = { Hook.tap = { taps += 1 } }()
        Text("x")
    }
}
@MainActor func poke(_ model: Model, _ legacy: Legacy) { model.stars = 3; legacy.stars = 4; Hook.tap?() }
