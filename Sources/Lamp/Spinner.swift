import SwiftUI

/// The chat keeps AppKit's controls out of its rows while a turn is running.
///
/// SwiftUI draws two things in the chat with an AppKit view: a spinner (ProgressView) and the overlay that
/// makes text selectable. Each time SwiftUI updates one of those views it tells the window its size may have
/// changed, and that makes SwiftUI lay the chat out again. While a turn is running the chat's rows are
/// re-measured all the time, and if the side panel opens or closes just then the two never stop answering each
/// other: Lamp hangs, or AppKit gives up after as many rounds as the window has views and raises an exception
/// that quits Lamp in the middle of the turn. (Seen on macOS 26.) So spinners here are drawn by SwiftUI
/// itself, and text is selectable only once the turn is over.

/// The spinner for everything in the main window that says "working": an animated symbol, not ProgressView.
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

private struct ChatTextSelectableKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False in a chat whose turn is still running: see `selectable()`.
    var chatTextSelectable: Bool {
        get { self[ChatTextSelectableKey.self] }
        set { self[ChatTextSelectableKey.self] = newValue }
    }
}

extension View {
    /// Text the user can select and copy, except while the chat's turn is running (see the top of this file).
    func selectable() -> some View { modifier(Selectable()) }
}

private struct Selectable: ViewModifier {
    @Environment(\.chatTextSelectable) private var selectable

    func body(content: Content) -> some View {
        if selectable {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}
