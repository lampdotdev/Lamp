import Foundation
struct Color3 { var r: Float = 1 }
struct Vertex { var x: Float = 0; var c = Color3() }
struct Label { var text = "a"; var size = 2 }
final class Scene { var label = Label(); var verts = [Vertex(), Vertex()]
    func show() -> String { "\(label.text) size=\(label.size) stride=\(Bytes.stride()) bytes=\(Bytes.count(verts))" } }
