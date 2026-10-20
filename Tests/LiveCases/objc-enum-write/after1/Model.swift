import Foundation
@objc enum Mood: Int { case happy, sad }
struct Cell { var mood: Mood; var flag: Bool; var n: UInt8 }
final class Store { var cell = Cell(mood: .sad, flag: true, n: 200); var moods: [Mood] = [.sad, .happy, .sad] }
func flip(_ s: Store) { s.cell.mood = .happy; s.moods[1] = .sad }
func show(_ s: Store) -> String { "mood=\(s.cell.mood.rawValue) flag=\(s.cell.flag) n=\(s.cell.n) moods=\(s.moods.map(\.rawValue)) size=\(MemoryLayout<Cell>.size)" }
