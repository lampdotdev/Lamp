import SwiftUI

/// What the GitHub cards (`RepoCard`, `ContributeCard`) share: their layout, and the fold of their sources' own terms.

/// A GitHub card's words with its buttons under them. In the chat's place (`scrolls`), a card too tall for the panel
/// scrolls its words and keeps its buttons at the bottom, so they're never out of sight; one that fits is drawn as on
/// its own, a single block.
struct GitHubCardLayout<Content: View, Buttons: View>: View {
    let scrolls: Bool
    let width: CGFloat?
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons

    var body: some View {
        if scrolls {
            // Whatever the card shows open (the fold of terms) is kept by the card, so moving between the two doesn't
            // close it.
            ViewThatFits(in: .vertical) {
                block
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) { content }
                            .padding([.horizontal, .top], 24)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    buttons.padding(.horizontal, 24).padding(.vertical, 16)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            block
        }
    }

    private var block: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
            buttons
        }
        .padding(24)
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// The lines of sources that are only credited under their own terms. One is shown as it is; several fold under one
/// line, so a wish built on many data sets doesn't bury the card under them.
struct TermsFold: View {
    let terms: [String]
    @Binding var open: Bool

    var body: some View {
        if terms.count == 1 {
            line(terms[0])
        } else if !terms.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button { open.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0)).imageScale(.small)
                        Text("Licenses of \(terms.count) sources")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .font(.callout).foregroundStyle(.secondary)
                .accessibilityValue(open ? "Shown" : "Hidden")
                if open { ForEach(terms, id: \.self, content: line) }
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
