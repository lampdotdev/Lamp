import SwiftUI
import AppKit

@main
struct LampApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    /// Not observed here. A scene that observes the store is built again on every change to it, and every window
    /// with it: a message sent redrew Lamp's window, the desk behind it and each wish's window, twice over. Each
    /// view observes the store itself, and so do the menu commands (`LampCommands`).
    /// Read when the scenes are built rather than when the App is made, which is before there is an NSApplication.
    private var store: Store { Store.shared }

    var body: some Scene {
        Window(Edition.name, id: "main") {
            ContentView()
                .environmentObject(store)
        }
        // Each wish's chat in a window of its own, listed in the Window menu like a document's.
        WindowGroup("Wish", id: "wish", for: String.self) { $id in
            WishWindow(id: $id)
                .environmentObject(store)
        }
        .defaultSize(width: 980, height: 720)
        .commandsRemoved()
        .commands { LampCommands(store: store) }
        Settings {
            SettingsView().environmentObject(store)
        }
        LampHelpScene()
        BugReportScene()
        AboutScene()
        GalleryScene()
    }
}

/// The menu bar's commands. They observe the store themselves, so whether Duplicate or Copy Wish File can be chosen
/// follows the selection without the scene around them being built again for every change (see `LampApp.store`).
struct LampCommands: Commands {
    @ObservedObject var store: Store

    var body: some Commands {
        AboutCommands()
        CheckForUpdatesCommand()
        LampHelpCommands()
        CommandGroup(replacing: .newItem) {
            Button("New Wish") { store.newWish() }
                .keyboardShortcut("n")
        }
        CommandGroup(after: .newItem) {
            Button("Import Shared Wish…") { store.chooseImport() }
                .keyboardShortcut("o")
            Button("Duplicate") { if let project = store.selected { Task { await store.duplicate(project) } } }
                .disabled(store.selected.map { store.busy.contains($0.id) || !$0.scaffolded || $0.untitled } ?? true)
        }
        CommandGroup(after: .pasteboard) {
            // The same as Share ▸ Copy Wish File in the toolbar; here so the shortcut the Help lists exists.
            Button("Copy Wish File") { if let project = store.selected { store.copyAppFile(project) } }
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
        CommandGroup(after: .windowArrangement) { GalleryCommand() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Before launch finishes, so clicking a notification that launched Lamp still opens its chat.
    func applicationWillFinishLaunching(_ notification: Notification) {
        PhoneTools.restoreChoice()
        MainActor.assumeIsolated {
            Notifier.shared.start()
            MagicPanel.start()
            // Once the apps are read: an app whose sidebar is open finds Lamp again.
            DispatchQueue.main.async { SidebarServer.shared.start() }
        }
    }

    private let launched = Date()

    /// Generated apps call back with lamp://edit?app=<slug> (⇧⌘E inside the app).
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            // An app's sidebar started Lamp: the chat is in that app, so Lamp's own window stays out of the way.
            // Opened already, it stays as it was. The Dock icon brings it back.
            let forSidebar = urls.contains { $0.scheme == Edition.urlScheme && $0.host == "sidebar" }
            if forSidebar, Date().timeIntervalSince(launched) < 5, Onboarding.isDone { MagicPanel.keepMainWindowHidden() }
            urls.forEach(Store.shared.handle(url:))
        }
    }

    /// The Dock icon shows Lamp's window, also when it was put away for an app's sidebar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            if let main = MagicPanel.mainWindow, !main.isVisible { main.makeKeyAndOrderFront(nil) }
        }
        return true
    }

    /// Closing Lamp's window quits it, except while an app's sidebar is open: Lamp is still in use there.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { !SidebarServer.shared.isInUse }
    }

    /// Quitting mid-turn would leave the agent and its build running on their own, and the gateway the
    /// agent is talking to gone: ask first, and stop them if the user quits anyway.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            // A Stop a moment ago may still have processes on their two seconds' notice; they go now.
            Subprocess.killStopping()
            guard Store.shared.isWorking else { return .terminateNow }
            let alert = NSAlert()
            alert.messageText = "A wish is still being worked on. Quit anyway?"
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
            Store.shared.flushChats()
            LocalModels.shared.stopServer()
        }
    }
}
