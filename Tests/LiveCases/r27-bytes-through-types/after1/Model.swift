import Foundation
typealias RGB = Color3
struct Color3 { var r: Float = 1; var g: Float = 0 }
struct Vertex { var x: Float = 0; var c: RGB = Color3() }
struct Packet { var id: Int32 = 0 }
final class Scene { func show() -> String { "stride=\(MemoryLayout<Vertex>.stride) bytes=\(Bytes.count())" } }
