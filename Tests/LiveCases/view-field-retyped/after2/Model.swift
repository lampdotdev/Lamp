import SwiftUI
struct RailText: View {
    var label: String
    var heat: Int?
    var body: some View { Text(reading) }
    var reading: String { "\(label) heat=\(heat.map(String.init) ?? "none")" }
}
typealias RowAlias = RailText
final class Cache { var row = RowAlias(label: "kept", heat: 2) }
// The rail is made where an app makes its views: by a view's body, here through a helper it calls.
struct Shelf: View { var body: some View { Self.rail() }; static func rail() -> RailText { RailText(label: "IPA", heat: 7) } }
@MainActor func probe() -> String { Shelf.rail().reading + " " + Cache().row.reading }
