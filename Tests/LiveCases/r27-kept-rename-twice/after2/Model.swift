import Foundation
struct Panel { var selection: Int { 7 }; var note = "x" }
final class Owner { var panel = Panel(); func show() -> String { "\(panel.selection) \(panel.note)!" } }
