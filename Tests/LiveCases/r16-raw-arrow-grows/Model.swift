import Foundation
enum Arrow: String, CaseIterable { case back = "<-", next = "->" }
func show() -> String { Arrow.allCases.map(\.rawValue).joined(separator: " ") }
