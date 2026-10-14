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
                Button("Duplicate") { if let project = store.selected { Task { await store.duplicate(project) } } }
                    .disabled(store.selected.map { store.busy.contains($0.id) || !$0.scaffolded || $0.untitled } ?? true)
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
        BugReportScene()
        AboutScene()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Before launch finishes, so clicking a notification that launched Lamp still opens its chat.
    func applicationWillFinishLaunching(_ notification: Notification) {
        PhoneTools.restoreChoice()
        MainActor.assumeIsolated {
            Notifier.shared.start()
            MagicPanel.start()
        }
    }

    private let launched = Date()

    /// Generated apps call back with lamp://edit?app=<slug> (⇧⌘E inside the app).
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            // An app's wand started Lamp: the chat beside that app is what was asked for, so Lamp's own window
            // stays out of the way. Opened already, it stays as it was. The Dock icon brings it back.
            let forPanel = urls.contains { $0.scheme == Edition.urlScheme && $0.host == "magic" }
            if forPanel, Date().timeIntervalSince(launched) < 5, Onboarding.isDone { MagicPanel.keepMainWindowHidden() }
            urls.forEach(Store.shared.handle(url:))
        }
    }

    /// The Dock icon shows Lamp's window, also when only an app's chat panel was open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            if let main = MagicPanel.mainWindow, !main.isVisible { main.makeKeyAndOrderFront(nil) }
        }
        return true
    }

    /// Closing Lamp's window quits it, except while an app's chat panel is open (the wand's): then Lamp's window
    /// was put away for the panel, and Lamp is still in use.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { !MagicPanel.shared.isOpen }
    }

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
