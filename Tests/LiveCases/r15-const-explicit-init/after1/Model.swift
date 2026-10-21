import Foundation
struct Settings { var volume = 7; var name: String; init() { name = "main" } }
enum Defaults { static let settings = Settings() }
func show() -> String { "constant=\(Defaults.settings.volume) fresh=\(Settings().volume)" }
