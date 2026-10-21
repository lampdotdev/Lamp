import SwiftUI
struct RailText: View {
    var label: String
    var heat: String?
    var body: some View { Text(reading) }
    var reading: String { "\(label) heat=\(heat ?? "none")" }
}
@MainActor func probe() -> String { RailText(label: "IPA", heat: "hot").reading }
