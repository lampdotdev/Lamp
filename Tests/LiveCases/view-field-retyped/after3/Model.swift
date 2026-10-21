import SwiftUI
private typealias UInt64 = String
struct RailText: View {
    var label: String
    fileprivate var heat: UInt64? = "hot"
    var body: some View { Text(reading) }
    var reading: String { "\(label) heat=\(heat ?? "none")" }
}
@MainActor func probe() -> String { RailText(label: "IPA").reading }
