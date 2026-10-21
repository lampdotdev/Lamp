import SwiftUI
struct Style { var title = "Card"; var offset: CGSize = .zero; var tint: Color = .blue }
func show(_ s: Style) -> String { "\(s.title) \(s.offset) \(s.tint == .blue)" }
