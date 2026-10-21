import SwiftUI
import AppKit

extension ChatLook {
    /// Undo Last Change, under the latest change in the chat: the toolbar's Undo, where the change happened. Small
    /// and plain, like the buttons beside the message box, so the change above it stays what the eye goes to.
    public struct UndoChange: View {
        let undo: () -> Void
        @State private var hovered = false

        public init(undo: @escaping () -> Void) { self.undo = undo }

        public var body: some View {
            Button(action: undo) {
                Label("Undo Last Change", systemImage: "arrow.uturn.backward")
                    .font(.callout)
                    .foregroundStyle(hovered ? .primary : .secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background {
                        Capsule().fill(Color(nsColor: .textBackgroundColor))
                            .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            // What the person must know to decide, kept out of sight until asked for: the code goes back, the data doesn't.
            .help("Puts the app back as it was before this change. What you saved in it stays.")
            // Its edge where the bubbles' and cards' is.
            .padding(.leading, ChatLook.tailRoom)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
