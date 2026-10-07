import SwiftUI
import AppKit

@main
struct LampApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        Window(Edition.name, id: "main") {
            ContentView()
                .environmentObject(store)
        }
        .commands {
            AboutCommands()
            CheckForUpdatesCommand()
            LampHelpCommands()
            CommandGroup(replacing: .newItem) {
                // A Mac app; with iOS apps on, the new app's intro offers iPhone and iPad instead.
                Button("New App") { store.create() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Button("Import Shared App…") { store.chooseImport() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .pasteboard) {
                // The same as Share ▸ Copy App File in the toolbar; here so the shortcut the Help lists exists.
                Button("Copy App File") { if let project = store.selected { store.copyAppFile(project) } }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(store.selected.map { !store.canShare($0) } ?? true)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Name This Version…") {
                    if let project = store.selected { Task { await store.nameCurrentVersion(of: project) } }
                }
                .keyboardShortcut("s")
                .disabled(store.selected == nil)
            }
        }
        Settings {
            SettingsView().environmentObject(store)
        }
        LampHelpScene()
        AboutScene()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Before launch finishes, so clicking a notification that launched Lamp still opens its chat.
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { Notifier.shared.start() }
    }

    /// Generated apps call back with lamp://edit?app=<slug> (⇧⌘E inside the app).
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            urls.forEach(Store.shared.handle(url:))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quitting mid-turn would leave the agent and its build running on their own, and the gateway the
    /// agent is talking to gone: ask first, and stop them if the user quits anyway.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            // A Stop a moment ago may still have processes on their two seconds' notice; they go now.
            Subprocess.killStopping()
            guard Store.shared.isWorking else { return .terminateNow }
            let alert = NSAlert()
            alert.messageText = "An app is still being worked on. Quit anyway?"
            alert.informativeText = "Quitting stops the work. Any changes made so far are kept; you can undo them later."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            // Not .terminateNow: the processes get a moment to quit (and are killed after two seconds; see
            // Subprocess.terminateTree), and Lamp waits for that rather than leaving them behind.
            let pids = Store.shared.stopAll()
            Task { @MainActor in
                for _ in 0..<40 where Subprocess.alive(pids) { try? await Task.sleep(for: .milliseconds(100)) }
                Subprocess.killStopping()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            _ = Store.shared.stopAll()   // for a quit that didn't go through the question above
            Subprocess.killStopping()
            Store.shared.flushDrafts()
            LocalModels.shared.stopServer()
        }
    }
}
