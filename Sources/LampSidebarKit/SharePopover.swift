import SwiftUI
import AppKit

/// What the chat's Share button opens: the wish's link first, to copy (or the way to make one), with the copies people
/// shared of it under it, then the Mac's own ways to send it, then the rest of sharing. It takes plain values and says what was chosen, so the gallery draws it as
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

    /// `openCopy` opens a copy's page, `allCopies` the link's own page (which lists every copy), and `compare` asks the
    /// agent what a copy changed.
    public enum Action: Equatable {
        case copyLink, makeLink, editLink, send(Way), contribute, copyFile, export
        case openCopy(URL), allCopies, compare(URL)
    }

    /// The most copies listed; the rest are on the link's page.
    public static let copiesShown = 5

    let link: URL?
    let copies: [SharedCopyRow]
    let canContribute: Bool
    let now: Date
    let act: (Action) -> Void
    @State private var copied = false

    public init(link: URL?, copies: [SharedCopyRow] = [], canContribute: Bool, now: Date = Date(), act: @escaping (Action) -> Void) {
        self.link = link
        self.copies = copies.filter { URL(string: $0.url) != nil }
        self.canContribute = canContribute
        self.now = now
        self.act = act
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            linkRow
            if link != nil, !copies.isEmpty { copyList }
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

    /// The copies people shared of the link, newest first: each opens its page, and Compare asks the agent what it changed.
    private var copyList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COPIES").font(.system(size: 10.5, weight: .bold)).tracking(1.1).foregroundStyle(Paper.label)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(copies.prefix(Self.copiesShown)) { copy in
                    if let url = URL(string: copy.url) {
                        CopyRow(name: copy.name.isEmpty ? "Untitled" : copy.name, detail: detail(of: copy), url: url,
                                open: { act(.openCopy(url)) }, compare: { act(.compare(url)) })
                    }
                }
                if copies.count > Self.copiesShown {
                    Row("\(copies.count - Self.copiesShown) More", "ellipsis") { act(.allCopies) }
                        .help("See every copy on the link's page")
                }
            }
            .padding(.horizontal, -6)
        }
    }

    /// "by Sam · 2 days ago": who shared it, and when it last changed.
    private func detail(of copy: SharedCopyRow) -> String {
        let by = copy.by.trimmingCharacters(in: .whitespaces)
        return [by.isEmpty ? nil : "by \(by)", copy.updated.flatMap(Self.date(from:)).map(when)].compactMap { $0 }.joined(separator: " · ")
    }

    /// Today, yesterday, a few days ago, or the day itself once it's a month or more.
    private func when(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "today"
        case 1: return "yesterday"
        case ..<30: return "\(days) days ago"
        default: return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    /// The site's dates, with or without fractions of a second.
    static func date(from text: String) -> Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: text) { return date }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: text)
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

/// One copy: its name and who shared it when, lit while pointed at and opening its page, with Compare at its end.
private struct CopyRow: View {
    let name: String
    let detail: String
    let url: URL
    let open: () -> Void
    let compare: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 11)).foregroundStyle(Paper.muted).lineLimit(1).truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(url.absoluteString)
            Button("Compare", action: compare)
                .buttonStyle(PaperButtonStyle(.outline, height: 24))
                .help("Ask what this copy changed")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(hovered ? Paper.bubble : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .onHover { hovered = $0 }
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
