import Foundation
enum Settings { static var volume = 1; static var brightness = 2 }
func show() -> String { "\(Settings.volume)" }
func late() -> String { "" }
