import Foundation
enum Settings { static var volume = 5; static var brightness = 9 }
func show() -> String { "\(Settings.volume)" }
func late() -> String { "\(Settings.brightness)" }
