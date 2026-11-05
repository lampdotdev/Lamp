import SwiftUI
import AppKit
import LampSidebarKit

/// The Share Link card's own window, one per wish, as big as the card and no bigger: opened from the chat's Share
/// button (beside an app or in Lamp's panel) and from the desk alike, so it's never in the chat's place. Closing it
/// closes the card, keeping the link.
@MainActor final class WishLinkWindows: NSObject, NSWindowDelegate {
    static let shared = WishLinkWindows()

    private var windows: [String: NSWindow] = [:]
    /// Closed by the card (Cancel, Done), so the window's closing doesn't close the card again.
    private var closingInternally = false

    func show(_ project: LampProject) {
        if windows[project.id] == nil {
            // Read once: it's a line about the wish's credits, which don't change while the card is open.
            let noLicense = ShareCheck.warningLine(Credits.load(project))
            let content = NSHostingController(rootView: WishLinkWindowContent(project: project, noLicense: noLicense))
            content.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: content)
            // Moved and closed, never resized: it fits what's on the card.
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "Share a Link to \(project.title)"
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(Paper.page)
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.center()
            windows[project.id] = window
        }
        // Asked for from another app's window too (the chat beside it), so Lamp comes forward with it.
        NSApp.activate(ignoringOtherApps: true)
        windows[project.id]?.makeKeyAndOrderFront(nil)
    }

    func close(_ project: LampProject) {
        guard let window = windows.removeValue(forKey: project.id) else { return }
        closingInternally = true
        window.close()
        closingInternally = false
    }

    /// Not while the card is sending: a share in flight keeps its card, or a second Copy Link from a card opened again
    /// would make another link over the first's kept secret. The card itself is disabled meanwhile; this is the close button.
    func windowShouldClose(_ window: NSWindow) -> Bool {
        guard let id = windows.first(where: { $0.value === window })?.key else { return true }
        return WishLinkCards.shared.cards[id]?.stage != .sending
    }

    func windowWillClose(_ notification: Notification) {
        guard !closingInternally, let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        windows[id] = nil
        if let project = Store.shared.projects.first(where: { $0.id == id }) { WishLinkCards.shared.close(project) }
    }
}

/// The card as the window draws it, from what `WishLinkCards` has for the wish.
private struct WishLinkWindowContent: View {
    @ObservedObject private var cards = WishLinkCards.shared
    let project: LampProject
    let noLicense: String?

    var body: some View {
        if let card = cards.card(for: project) {
            WishLinkCard(icon: card.iconImage, picture: card.image,
                         values: Binding(get: { card.values }, set: { cards.update(project, values: $0) }),
                         limits: WishLink.cardLimits, link: card.shared?.url.absoluteString, changed: card.changed,
                         stage: card.stage, copied: card.copied,
                         retake: cards.canRetake(project) ? { cards.retake(project) } : nil, retaking: card.retaking,
                         canIncludeFile: card.values.includeFile || (card.gitHub != nil && card.values.alsoGitHub)
                            || (card.values.putOnGitHub && card.firstPush?.isPublic == true), noLicense: noLicense,
                         writingNotes: card.writingNotes, gitHub: card.gitHub?.repo, gitHubNote: card.gitHubNote, gitHubStage: card.gitHubStage,
                         retryGitHub: card.gitHubRetry == nil ? nil : { cards.retryGitHub(project) },
                         gitHubSetup: card.firstPush.map { GitHubRelease.setup($0, of: project) },
                         setUpGitHub: .init(fix: { cards.fixGitHub(project) }, setPrivate: { cards.setGitHubPrivate(project, $0) },
                                            setLicense: { cards.setGitHubLicense(project, $0) }, setPicture: { cards.setGitHubPicture(project, $0) }),
                         share: { cards.share(project) }, copy: { cards.copy(project) }, stop: { cards.stop(project) },
                         close: { cards.close(project) }, width: 440)
                // Under the window's clear title bar, so the close button sits on the card.
                .padding(.top, 12)
        }
    }
}
