import Foundation
struct Settings { var volume = 7 }
enum Current { static var settings = Settings() }
func show() -> String { "static=\(Current.settings.volume) fresh=\(Settings().volume)" }
