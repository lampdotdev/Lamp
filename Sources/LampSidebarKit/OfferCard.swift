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
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: done ? "checkmark" : symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(shape.fill(LinearGradient(colors: done ? [Color.green.opacity(0.85), Color.green]
                                                          : [Color.accentColor.opacity(0.85), Color.accentColor],
                                                          startPoint: .top, endPoint: .bottom)))
                    .overlay(shape.strokeBorder(.black.opacity(0.08)))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(status).font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                buttons.controlSize(.small)
            }
            .padding(14)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        }
    }

    /// A line offering one thing to do, like Draw Icon: a symbol, what's so, and the button.
    public struct ActionLine: View {
        let symbol: String
        let text: String
        let button: String
        let disabled: Bool
        /// The one thing to do next (Reload, for a change waiting on it): the button in the accent colour.
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
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text(text).foregroundStyle(.secondary)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
