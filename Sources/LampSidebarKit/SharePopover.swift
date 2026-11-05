import SwiftUI
import AppKit

/// What the chat's Share button opens: the wish's link first, to copy (or the way to make one), then the Mac's own ways
/// to send it, then the rest of sharing. It takes plain values and says what was chosen, so the gallery draws it as
/// people see it and the chat does the rest.
public struct SharePopover: View {
    /// The Mac's ways to send: the link when there is one, else the wish's file.
    public enum Way: CaseIterable, Equatable {
        case airDrop, messages, mail, more

        /// The system's service for it; More is the system's whole list instead.
        public var service: NSSharingService? {
            switch self {
            case .airDrop: NSSharingService(named: .sendViaAirDrop)
            case .messages: NSSharingService(named: .composeMessage)
            case .mail: NSSharingService(named: .composeEmail)
            case .more: nil
            }
        }
    }

    public enum Action: Equatable { case copyLink, makeLink, editLink, send(Way), contribute, copyFile, export }

    let link: URL?
    let canContribute: Bool
    let act: (Action) -> Void
    @State private var copied = false

    public init(link: URL?, canContribute: Bool, act: @escaping (Action) -> Void) {
        self.link = link
        self.canContribute = canContribute
        self.act = act
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            linkRow
            ways
            Rectangle().fill(Paper.rule).frame(height: 1)
            VStack(alignment: .leading, spacing: 0) {
                if canContribute { Row("Send Changes Back…", "arrow.triangle.branch") { act(.contribute) } }
                Row("Copy App File", "doc.on.doc") { act(.copyFile) }
                Row("Export…", "square.and.arrow.down") { act(.export) }
            }
            .padding(.horizontal, -6)
        }
        .padding(14)
        .frame(width: 330)
        .foregroundStyle(Paper.ink)
        .background(Paper.page)
    }

    @ViewBuilder private var linkRow: some View {
        if let link {
            HStack(spacing: 8) {
                // The address as people read it, without the scheme; the whole of it is what's copied.
                Text((link.host ?? "") + link.path)
                    .font(.system(size: 13))
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .background(Paper.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Paper.rule))
                    .help(link.absoluteString)
                Button {
                    act(.copyLink)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(PaperButtonStyle(.outline, square: true))
                .help(copied ? "Copied" : "Copy the link")
                .accessibilityLabel(copied ? "Copied" : "Copy Link")
                // The link's window: what it shows, a new release of the app, or taking it down.
                Button("New Release") { act(.editLink) }
                    .buttonStyle(PaperButtonStyle(.ink))
                    .help("Put the app as it is now on the link, or change what the link shows")
            }
        } else {
            Button { act(.makeLink) } label: {
                Label("Make a Link…", systemImage: "link").frame(maxWidth: .infinity)
            }
            .buttonStyle(PaperButtonStyle(.ink))
            .help("A page on lamp.dev anyone can open to try this app and make their own")
        }
    }

    private var ways: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Way.allCases.filter { $0 == .more || $0.service != nil }, id: \.self) { way in
                WayButton(way: way) { act(.send(way)) }
                    .frame(maxWidth: .infinity)
            }
        }
        .help(link == nil ? "Send the app's file" : "Send the link")
    }
}

/// One of the Mac's ways to send, as its icon and name.
private struct WayButton: View {
    let way: SharePopover.Way
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if let image = way.service?.image {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 36, height: 36)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Paper.card, in: Circle())
                        .overlay(Circle().strokeBorder(Paper.rule))
                }
                Text(way.service?.title ?? "More")
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A line of the rest of sharing, lit while pointed at, as a menu's items are.
private struct Row: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovered = false

    init(_ title: String, _ symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // One column for the symbols, so the words line up whatever their width.
                Image(systemName: symbol).frame(width: 18)
                Text(title)
            }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .padding(.horizontal, 6)
                .background(hovered ? Paper.bubble : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
