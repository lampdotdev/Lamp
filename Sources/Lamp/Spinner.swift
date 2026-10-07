import SwiftUI

/// The spinner for everything in the main window that says "working": an animated symbol drawn by SwiftUI,
/// not ProgressView.
///
/// ProgressView puts an AppKit progress indicator in the window. Each time SwiftUI makes or updates one, it
/// tells the window its size may have changed, and that makes SwiftUI lay the chat out again. While a turn
/// is running the chat's rows are re-measured all the time, and if the side panel opens or closes just
/// then, that layout can fail to settle: Lamp hangs, or AppKit gives up after as many rounds as the window
/// has views and raises an exception that quits Lamp in the middle of the turn. (Seen on macOS 26.) With
/// the spinners drawn by SwiftUI it happened far less often when tried, though not never: the chat's own
/// layout can still do it.
struct Spinner: View {
    enum Size: CGFloat {
        case mini = 10, small = 16
    }

    private let side: CGFloat

    init(_ size: Size = .small) { side = size.rawValue }
    init(side: CGFloat) { self.side = side }

    var body: some View {
        Image(systemName: "progress.indicator")
            .resizable()
            .scaledToFit()
            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeating)
            .foregroundStyle(.secondary)
            .frame(width: side, height: side)
            .accessibilityLabel("Working")
    }
}
