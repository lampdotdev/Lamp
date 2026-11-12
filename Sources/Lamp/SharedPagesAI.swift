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
    static let routes: Set<String> = ["/ai/status", "/ai", "/ai/act", "/ai/decide", "/ai/hear", "/ai/image"]

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
            let (status, reply) = await Store.shared.sharedPageAI(path: path, body: event["body"] as? [String: Any] ?? [:])
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
