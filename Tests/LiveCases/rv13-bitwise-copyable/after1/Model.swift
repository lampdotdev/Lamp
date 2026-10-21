import Foundation
// One struct anywhere in the app that says it's bitwise-copyable.
struct Pixel: BitwiseCopyable { var r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0 }
final class Game { var level = 1; var lives = 3; func show() -> String { "level=\(level) lives=\(lives)" } }
