import SwiftUI

extension ChatLook {
    /// A request in the chat: what was attached, the bubble, and the buttons beside it that show when pointed at:
    /// going back to how the app was around it, and taking it back into the message box to change and send again.
    public struct UserRow<Attachments: View>: View {
        let text: String
        let busy: Bool
        let goBack: ((Bool) -> Void)?
        let sendAgain: (() -> Void)?
        /// The latest request shows its Send Again button all the time, so there's one to find; earlier ones
        /// show it when pointed at.
        let isLatest: Bool
        let attachments: Attachments
        @State private var hovered = false

        /// `goBack` is there when the request made a version (true: to the one before it); `sendAgain` when it
        /// can be sent again now.
        public init(text: String, busy: Bool, goBack: ((Bool) -> Void)?, sendAgain: (() -> Void)?, isLatest: Bool,
                    @ViewBuilder attachments: () -> Attachments) {
            self.text = text
            self.busy = busy
            self.goBack = goBack
            self.sendAgain = sendAgain
            self.isLatest = isLatest
            self.attachments = attachments()
        }

        public var body: some View {
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) { attachments }
                HStack(alignment: .center, spacing: 6) {
                    if let goBack {
                        Menu {
                            Button("Go Back to After This Change") { goBack(false) }
                            Button("Go Back to Before This Change") { goBack(true) }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .foregroundStyle(.secondary)
                        .disabled(busy)
                        .opacity(hovered ? 1 : 0)
                        .help("Go back to how the app was around this request")
                    }
                    if let sendAgain {
                        Button(action: sendAgain) { Image(systemName: "pencil") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .opacity(hovered || isLatest ? 1 : 0)
                            .help("Change this message and send it again")
                            .accessibilityLabel("Edit and Send Again")
                    }
                    // A message that's only attachments shows just them.
                    if !text.isEmpty { UserBubble(text) }
                }
                // The width limit goes around the buttons too, so they stay next to a short message.
                .frame(maxWidth: 480 + 50, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .onHover { hovered = $0 }
        }
    }
}
