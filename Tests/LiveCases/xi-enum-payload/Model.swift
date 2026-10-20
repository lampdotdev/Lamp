import Foundation
enum Mood { case happy, sad }
// One payload case carrying the enum: the no-payload cases are Mood's extra inhabitants.
enum Phase { case idle, running(Mood), done }
// A struct holding it plainly, and a class holding the struct plainly.
struct Row { var phase: Phase; var n: Int }
final class Holder {
    var phase: Phase = .idle
    var phases: [Phase] = [.idle, .running(.sad), .done]
    var row = Row(phase: .done, n: 1)
    var rows: [Row] = [Row(phase: .idle, n: 2)]
}
func describe(_ h: Holder) -> String {
    func p(_ x: Phase) -> String { switch x { case .idle: "idle"; case .running(let m): "running(\(m))"; case .done: "done" } }
    return "phase=\(p(h.phase)) phases=\(h.phases.map(p)) row=\(p(h.row.phase)) rows=\(h.rows.map { p($0.phase) })"
}
