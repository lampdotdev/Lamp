import Foundation
private class Shape { func area() -> Int { 0 }; var name: String { "shape" } }
private final class Square: Shape { override func area() -> Int { 9 }; override var name: String { "SQUARE" } }
enum Shapes {
    private static let all: [Shape] = [Shape(), Square()]
    static func describe() -> String { all.map { "\($0.area())" }.joined(separator: " ") + " " + all.map(\.name).joined(separator: " ") }
}
