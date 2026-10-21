import Foundation
struct Settings { var volume = 5 }
enum Defaults { static let settings = Settings() }
func show() -> String { "constant=\(Defaults.settings.volume) fresh=\(Settings().volume)" }
