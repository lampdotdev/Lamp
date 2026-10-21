import SwiftUI
struct RailText: View {
    var label: String
    var heat: Double?
    var body: some View { Text(reading) }
    var reading: String { "\(label) heat=\(heat.map { String(format: "%.1f", $0) } ?? "none")" }
}
// The rail is made where an app makes its views: by a view's body, here through a helper it calls.
struct Shelf: View { var body: some View { Self.rail() }; static func rail() -> RailText { RailText(label: "IPA", heat: 6.5) } }
@MainActor func probe() -> String { Shelf.rail().reading }
