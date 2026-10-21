import SwiftUI
struct RailText: View {
    var label: String
    var heat: Double?
    var body: some View { Text(reading) }
    var reading: String { "\(label) heat=\(heat.map { String(format: "%.1f", $0) } ?? "none")" }
}
@MainActor func probe() -> String { RailText(label: "IPA", heat: 6.5).reading }
