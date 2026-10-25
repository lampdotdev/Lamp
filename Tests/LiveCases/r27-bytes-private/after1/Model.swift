import Foundation
struct Color4 { var r: Float = 1; var g: Float = 0 }
func makeColor() -> Color4 { Color4() }
private struct Quad { var x: Float = 0; var c = makeColor() }
func show() -> String { "stride=\(MemoryLayout<Quad>.stride)" }
