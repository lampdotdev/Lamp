import Foundation
private class Shape { func area() -> Int { 0 }; var name: String { "shape" } }
private final class Square: Shape { override func area() -> Int { 4 }; override var name: String { "square" } }
enum Shapes {
    private static let all: [Shape] = [Shape(), Square()]
    static func describe() -> String { all.map { "\($0.area())" }.joined(separator: " ") + " " + all.map(\.name).joined(separator: " ") }
}
