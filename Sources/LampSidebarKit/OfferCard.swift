import SwiftUI

extension ChatLook {
    /// A card's header, as the setup offer and the widget card have it: a badge for what it's about, a headline
    /// and one gray line, and whatever buttons go with it.
    public struct OfferCard<Buttons: View>: View {
        let symbol: String
        let title: String
        let status: String
        /// Done: a green badge with a check where the symbol was, and the status as a line marked done.
        let done: Bool
        let buttons: Buttons

        public init(symbol: String, title: String, status: String, done: Bool, @ViewBuilder buttons: () -> Buttons = { EmptyView() }) {
            self.symbol = symbol
            self.title = title
            self.status = status
            self.done = done
            self.buttons = buttons()
        }

        public var body: some View {
            // The buttons beside the words where they fit, else under them, at the trailing edge.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    header
                    Spacer(minLength: 8)
                    buttons.cardButtons()
                }
                VStack(alignment: .trailing, spacing: 10) {
                    header.frame(maxWidth: .infinity, alignment: .leading)
                    buttons.cardButtons()
                }
            }
            .padding(14)
            .background(Paper.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Paper.rule))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        }

        private var header: some View {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            return HStack(alignment: .center, spacing: 12) {
                Image(systemName: done ? "checkmark" : symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(done ? Color.white : Paper.onInk)
                    .frame(width: 40, height: 40)
                    .background(shape.fill(LinearGradient(colors: done ? [Color.green.opacity(0.85), Color.green]
                                                          : [Paper.ink.opacity(0.85), Paper.ink],
                                                          startPoint: .top, endPoint: .bottom)))
                    .overlay(shape.strokeBorder(.black.opacity(0.08)))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(status).font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// A line offering one thing to do, like Draw Icon: a symbol, what's so, and the button. Laid out as a status
    /// line is (`StatusLine`): its symbol in the steps' column and its words in their size, in line with the agent's
    /// bubbles and "Worked for…" around it.
    public struct ActionLine: View {
        let symbol: String
        let text: String
        let button: String
        let disabled: Bool
        /// The one thing to do next (Reload, for a change waiting on it): the button in the accent color.
        let prominent: Bool
        let action: () -> Void

        public init(symbol: String, text: String, button: String, disabled: Bool = false, prominent: Bool = false,
                    action: @escaping () -> Void) {
            self.symbol = symbol
            self.text = text
            self.button = button
            self.disabled = disabled
            self.prominent = prominent
            self.action = action
        }

        public var body: some View {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
                Text(text).font(ChatLook.stepFont).foregroundStyle(.secondary)
                if prominent {
                    Button(button, action: action)
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .disabled(disabled)
                } else {
                    Button(button, action: action)
                        .controlSize(.small)
                        .disabled(disabled)
                }
            }
            .font(ChatLook.stepFont)
            .padding(.leading, ChatLook.stepIndent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
