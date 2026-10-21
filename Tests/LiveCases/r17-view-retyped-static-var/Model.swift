import SwiftUI
struct Meter: View {
    var label: String
    var level: Int
    var body: some View { Text(reading) }
    var reading: String { "\(label) level=\(level)" }
}
enum Shelf { static var pinned = Meter(label: "IPA", level: 3) }
var lastMeter = Meter(label: "Stout", level: 4)
@MainActor func probe() -> String { Shelf.pinned.reading + " / " + lastMeter.reading }
