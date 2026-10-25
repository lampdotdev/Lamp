import Foundation
struct Panel { var selection = 1; var note = "x" }
final class Owner { var panel = Panel(); func show() -> String { "\(panel.selection) \(panel.note)" } }
