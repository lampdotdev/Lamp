import SwiftUI
struct RailText: View {
    var label: String
    var heat: Int?
    var body: some View { Text(reading) }
    var reading: String { "\(label) heat=\(heat.map(String.init) ?? "none")" }
}
typealias RowAlias = RailText
final class Cache { var row = RowAlias(label: "kept", heat: 2) }
@MainActor func probe() -> String { RailText(label: "IPA", heat: 7).reading + " " + Cache().row.reading }
