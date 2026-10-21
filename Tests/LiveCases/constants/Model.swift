import Foundation
struct Size { var w: Double; var h: Double }
final class Engine { var name = "e" }
enum Config { static let speed = 2.0; static let double = speed * 2; static let label = "small" }
let defaultSize = Size(w: 1, h: 2)
let engine = Engine()
func report() -> String { "\(Config.speed) / \(Config.double) / \(Config.label) / \(defaultSize.w) / \(engine.name)" }
