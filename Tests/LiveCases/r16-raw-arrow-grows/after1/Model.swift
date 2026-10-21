import Foundation
enum Arrow: String, CaseIterable { case back = "<-", next = "->", up = "^" }
func show() -> String { Arrow.allCases.map(\.rawValue).joined(separator: " ") }
