import SwiftUI
struct RailText: View {
    var label: String
    var heat: Int?
    var body: some View { Text(reading) }
    var reading: String { "\(label) heat=\(heat.map(String.init) ?? "none")" }
}
@MainActor func probe() -> String { RailText(label: "IPA", heat: 3).reading }
