import Foundation
// A constant made from a type whose defaults are made by another type's defaults, or by a function.
struct Audio { var volume = 5 }
struct Settings { var audio = Audio(); var name = "main" }
func startLevel() -> Int { 1 }
struct Game { var level = startLevel() }
enum Defaults { static let settings = Settings(); static let game = Game() }
func show() -> String { "constant=\(Defaults.settings.audio.volume) fresh=\(Settings().audio.volume) level=\(Defaults.game.level) fresh=\(Game().level)" }
