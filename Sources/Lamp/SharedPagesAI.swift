import SwiftUI
import AppKit
import Foundation

/// The AI of a page shared on lamp.dev, played in a browser on this Mac, answered by Lamp with the AI the person set up
/// for their apps. Which pages are let in and how is lamp's command line's (`sharedPages` in cli/calls.mjs, the same
/// server `lamp ai` runs: cli/local-ai.mjs), so it's done once: Lamp keeps that call running, and it asks Lamp for the
/// two things that are Lamp's, the person's yes or no to a page, and the AI's answer (`Store.sharedPageAI`).
///
/// One port answers for the whole computer, so whichever of Lamp or `lamp ai` takes it first answers. One that finds
/// it taken tries again now and then, and takes it once the other lets go. A worktree's instance or the tests' never
/// does (`Edition.answersSharedPages`).
enum SharedPagesAI {
    /// What a shared page may ask (local-ai.mjs's `ROUTES`): never a route of the agent's or another app's.
    static let routes: Set<String> = ["/ai/status", "/ai/models", "/ai", "/ai/act", "/ai/decide", "/ai/hear", "/ai/image"]

    @MainActor private static var started = false

    @MainActor static func start() {
        guard Edition.answersSharedPages, !started else { return }
        started = true
        Task.detached {
            while true {
                _ = try? await LampCLI.ask("sharedPages", [:]) { event in
                    Task { @MainActor in await heard(event) }
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    @MainActor private static func heard(_ event: [String: Any]) async {
        if let n = event["ask"] as? Int {
            let yes = await askInDialog(name: event["name"] as? String ?? "", id: event["id"] as? String ?? "")
            _ = try? await LampCLI.ask("sharedPagesReply", ["n": n, "yes": yes])
        } else if let n = event["answer"] as? Int, let path = event["path"] as? String {
            let (status, reply) = await Store.shared.sharedPageAI(path: path, body: event["body"] as? [String: Any] ?? [:], page: event["id"] as? String ?? "")
            _ = try? await LampCLI.ask("sharedPagesReply", ["n": n, "status": status, "reply": reply])
        }
    }

    /// The person's yes or no to a page using their AI. lamp's command line asks about one page at a time.
    @MainActor static func askInDialog(name: String, id: String) async -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = name.isEmpty ? "Let a shared page use your AI?" : "Let “\(name)” use your AI?"
        alert.informativeText = "It's open in your browser, shared at lamp.dev/w/\(id). It can ask the AI you set up in \(Edition.name) for your apps."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Settings → Apps: the pages shared on lamp.dev allowed to use the person's AI on this Mac, each with Remove, which
/// has it ask again the next time. The list is the computer's, kept by lamp's command line, so it's the same whether
/// Lamp or `lamp ai` answered (`sharedPagesAllowed`, `sharedPagesForget`). Shown only once a page has been allowed;
/// the tab reads the list as it appears (`load`), since an empty section is never drawn to read it itself.
@MainActor final class SharedPagesAllowed: ObservableObject {
    struct Page: Identifiable, Equatable {
        let origin: String, id: String, name: String, at: Date?
    }
    @Published private(set) var pages: [Page] = []

    func load() async {
        guard let done = try? await LampCLI.ask("sharedPagesAllowed", [:]) else { return }
        let fraction = ISO8601DateFormatter()
        fraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        pages = (done["pages"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let origin = raw["origin"] as? String, let id = raw["id"] as? String else { return nil }
            let at = (raw["at"] as? String).flatMap { fraction.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return Page(origin: origin, id: id, name: raw["name"] as? String ?? "", at: at)
        }
    }

    func remove(_ page: Page) async {
        _ = try? await LampCLI.ask("sharedPagesForget", ["origin": page.origin])
        await load()
    }
}

struct SharedPagesSection: View {
    @ObservedObject var allowed: SharedPagesAllowed

    var body: some View {
        if !allowed.pages.isEmpty {
            Section("Shared pages using your AI") {
                ForEach(allowed.pages) { page in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(page.name.isEmpty ? "lamp.dev/w/\(page.id)" : page.name)
                            if let at = page.at {
                                Text("Allowed \(at.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .help("lamp.dev/w/\(page.id)")
                        Spacer()
                        Button("Remove") { Task { await allowed.remove(page) } }
                    }
                }
            }
        }
    }
}
