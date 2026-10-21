import Foundation
struct Settings { var volume = 7 }
enum Defaults { static let settings = Settings() }
func show() -> String { "constant=\(Defaults.settings.volume) fresh=\(Settings().volume)" }
