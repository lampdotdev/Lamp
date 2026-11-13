import SwiftUI
import LampSidebarKit

/// The copies people shared of each wish's link, as its page on the site lists them, for the chat's Share popover to
/// show (`SidebarToolbar.copies`). The chat's state is made many times a second while a turn runs, so the site is asked
/// only when what's kept is old (`stale`), or sooner when the popover opens (`fresh`), never once per state; a link
/// asked about stays asked once until the answer comes. When the site can't be asked, what was known stays, and a link
/// never answered shows none.
@MainActor
final class WishCopies: ObservableObject {
    static let shared = WishCopies()

    /// What's kept is asked for again after this long while a chat shows it.
    static let stale: TimeInterval = 5 * 60
    /// Opening the popover asks again after this long, so opening it twice in a row asks once.
    static let fresh: TimeInterval = 30

    private struct Kept {
        var rows: [SharedCopyRow]?
        var asked: Date
    }

    /// By the link's id, so a wish that moves or is renamed keeps them.
    private var kept: [String: Kept] = [:]
    private var asking: Set<String> = []

    /// The copies known of the wish's link, newest first; nil with no link or none known. Asks again when they're old.
    func rows(for project: LampProject) -> [SharedCopyRow]? {
        guard let id = WishLink.kept(for: project)?.id else { return nil }
        ask(id, olderThan: Self.stale)
        return kept[id]?.rows.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The popover opened: asks again unless it was just asked.
    func refresh(_ project: LampProject) {
        guard let id = WishLink.kept(for: project)?.id else { return }
        ask(id, olderThan: Self.fresh)
    }

    private func ask(_ id: String, olderThan age: TimeInterval) {
        if let known = kept[id], Date().timeIntervalSince(known.asked) < age { return }
        guard asking.insert(id).inserted else { return }
        Task {
            let rows = await WishLink.copies(of: id)
            asking.remove(id)
            // Published changes reach every chat showing the wish (`SidebarServer.start`).
            objectWillChange.send()
            kept[id] = Kept(rows: rows ?? kept[id]?.rows, asked: Date())
        }
    }
}

/// Lamp's own Share… popover, which shows the link's copies as they come in from the site.
struct SharePopoverWithCopies: View {
    let project: LampProject
    let link: URL?
    let act: (SharePopover.Action) -> Void
    @ObservedObject private var copies = WishCopies.shared

    var body: some View {
        SharePopover(link: link, copies: copies.rows(for: project) ?? [], canContribute: Contribute.canContribute(project), act: act)
    }
}
