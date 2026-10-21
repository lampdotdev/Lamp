import SwiftUI
private typealias UInt64 = String
struct RailText: View {
    var label: String
    fileprivate var heat: UInt64? = "hot"
    var body: some View { Text(reading) }
    var reading: String { "\(label) heat=\(heat ?? "none")" }
}
// The rail is made where an app makes its views: by a view's body, here through a helper it calls.
struct Shelf: View { var body: some View { Self.rail() }; static func rail() -> RailText { RailText(label: "IPA") } }
@MainActor func probe() -> String { Shelf.rail().reading }
