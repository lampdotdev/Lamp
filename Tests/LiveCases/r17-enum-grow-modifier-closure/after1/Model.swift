import SwiftUI
import Combine
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { lines.append(line) }
    static func take() -> String { defer { lines = [] }; return lines.joined(separator: ", ") }
}
enum Ticks { @MainActor static let publisher = PassthroughSubject<Int, Never>() }
enum Mood: CaseIterable { case calm, busy, away }
@Observable final class Model { var mood: Mood = .calm }
// A modifier that listens, as apps write one: its handler is made by the modifier's body.
struct Listens: ViewModifier {
    var model: Model
    func body(content: Content) -> some View {
        content.onReceive(Ticks.publisher) { tick in
            switch model.mood {
            case .calm: Log.add("tick \(tick) calm v2")
            case .busy: Log.add("tick \(tick) busy v2")
            case .away: Log.add("tick \(tick) away v2")
            }
        }
    }
}
struct Root: View {
    var model: Model
    var body: some View { Text("x").modifier(Listens(model: model)) }
}
@MainActor func poke(_ model: Model) { model.mood = .away }
