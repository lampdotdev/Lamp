import SwiftUI
import AppKit

extension ChatLook {
    /// What the person pointed at in the app, as one small pill: what it is and what it's part of. In the message
    /// box a click on it points again and its × lets it go; in a sent request a click shows its picture. Nothing
    /// more: the app beside the chat already shows the thing itself, so the pill only has to say which one.
    public struct PointedPill: View {
        let title: String
        let detail: String?
        let chooseAgain: (() -> Void)?
        let preview: (() -> Void)?
        let remove: (() -> Void)?

        /// In the message box `remove` is there, and `chooseAgain` while the app is open to point at; in a sent
        /// request only `preview`.
        public init(title: String, detail: String?, chooseAgain: (() -> Void)? = nil, preview: (() -> Void)? = nil,
                    remove: (() -> Void)? = nil) {
            self.title = title
            self.detail = detail
            self.chooseAgain = chooseAgain
            self.preview = preview
            self.remove = remove
        }

        public var body: some View {
            // A pill on one line; where that would cut what it's part of short, the name over it, in a rounded box.
            ViewThatFits(in: .horizontal) {
                pill(stacked: false).background(Color.accentColor.opacity(0.1), in: Capsule())
                pill(stacked: true).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(detail.map { "Selected: \(title), \($0)" } ?? "Selected: \(title)")
        }

        private func pill(stacked: Bool) -> some View {
            HStack(alignment: stacked ? .top : .center, spacing: 5) {
                Group {
                    if let action = chooseAgain ?? preview {
                        Button(action: action) { label(stacked: stacked).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .help(chooseAgain != nil ? "Point at something else" : "Show what was pointed at")
                    } else {
                        label(stacked: stacked)
                    }
                }
                if let remove {
                    Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .help("Remove")
                        .accessibilityLabel("Remove")
                }
            }
            .font(.callout)
            .padding(.leading, 8).padding(.trailing, remove == nil ? 10 : 6).padding(.vertical, stacked ? 6 : 4)
        }

        private func label(stacked: Bool) -> some View {
            HStack(alignment: stacked ? .firstTextBaseline : .center, spacing: 5) {
                Image(systemName: "scope").foregroundStyle(Color.accentColor)
                if stacked {
                    VStack(alignment: .leading, spacing: 1) { name; whereItIs }
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    name.fixedSize()
                    whereItIs.fixedSize()
                }
            }
        }

        private var name: some View { Text(title).fontWeight(.medium) }

        @ViewBuilder private var whereItIs: some View {
            if let detail, !detail.isEmpty { Text(detail).foregroundStyle(.secondary) }
        }
    }
}
