import Foundation
struct Size { var w: Double; var h: Double }
final class Engine { var name = "e"; init(_ n: String = "e") { name = n } }
enum Config { static let speed = 3.0; static let double = speed * 2; static let label = "big" }
let defaultSize = Size(w: 5, h: 2)
let engine = Engine("f")
func report() -> String { "\(Config.speed) / \(Config.double) / \(Config.label) / \(defaultSize.w) / \(engine.name)" }
