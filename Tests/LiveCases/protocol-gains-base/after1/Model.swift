import Foundation
protocol Named { var name: String { get } }
protocol Shape: Named { func area() -> Double }
final class Circle: Shape { var r = 1.0; var name: String { "circle" }; func area() -> Double { 3.0 * r * r } }
final class Store { var shapes: [any Shape] = [Circle(), Circle()] }
func total(_ s: Store) -> Double { s.shapes.map { $0.area() }.reduce(0, +) }
