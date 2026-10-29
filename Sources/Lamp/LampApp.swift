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

    init() {
        // A release builds the starters it ships before it's signed (PrebuiltStarters), with this program.
        if ProcessInfo.processInfo.environment["PREBUILD_STARTERS"] == "1" {
            if CommandLine.arguments.contains(PrebuiltStarters.commandLineFlag) { PrebuiltStarters.runFromCommandLine() }
            if CommandLine.arguments.contains(PrebuiltStarters.restampFlag) { PrebuiltStarters.restampFromCommandLine() }
        }
        // Each starter as the repository it's put in on GitHub (`scripts/publish-starters.sh`).
        if ProcessInfo.processInfo.environment["STAGE_STARTERS"] == "1", CommandLine.arguments.contains(StarterRepos.commandLineFlag) {
            StarterRepos.stageFromCommandLine()
        }
        // And the player every game and screen on the Mac is a copy of, compiled by build.sh from the Swift this writes.
        if CommandLine.arguments.contains(GameKit.playerSourcesFlag) { GameKit.writePlayerSourcesFromCommandLine() }
    }

    var body: some Scene {
        // The desk, and only the desk: each wish's chat is beside whatever shows the wish (`ChatPanel`, `MagicPanel`).
        Window(Edition.name, id: "main") {
            ContentView()
                .environmentObject(store)
        }
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

/// The menu bar's commands. They observe the store themselves, so whether Remix or Copy Wish File can be chosen
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
            Button("Open from GitHub…") { store.chooseRepository() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Remix as a New Wish…") { if let project = store.selected { Task { await store.remix(project) } } }
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
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: nil) { [weak self] note in
            self?.previewClosed = note.object is TVPreview.Window
        }
        MainActor.assumeIsolated {
            // Opened at login to keep the person's phone apps opening (`PhoneRenewals.staysOpen`): Lamp works out of
            // sight, its window put away as it appears, and the Dock icon brings it back.
            if Self.launchedAtLogin, PhoneRenewals.staysOpen, Onboarding.isDone { MagicPanel.keepMainWindowHidden() }
            Notifier.shared.start()
            MagicPanel.start()
            // Once the apps are read: an app whose sidebar is open finds Lamp again.
            DispatchQueue.main.async { SidebarServer.shared.start() }
        }
    }

    /// Whether macOS opened Lamp as a login item: the open-application event it launches Lamp with says so, read while
    /// launch is under way.
    private static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication else { return false }
        // keyAELaunchedAsLoginItem, 'lgit', which Swift's Carbon headers don't bring.
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == 0x6C67_6974
    }

    private let launched = Date()
    /// The window closed last was a TV or device preview: Stop closes it, and so may the person, to stop the app.
    private var previewClosed = false

    /// Generated apps call back with lamp://edit?app=<slug> (⇧⌘E inside the app).
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            // An app's sidebar started Lamp, or its Reload button, or its chat asked for Lamp's panel: what the person
            // is doing is in that app, so Lamp's own window stays out of the way. Opened already, it stays as it was. The Dock icon brings it back.
            let forSidebar = urls.contains { $0.scheme == Edition.urlScheme && ($0.host == "sidebar" || $0.host == "reload" || $0.host == "chat") }
            if forSidebar, Date().timeIntervalSince(launched) < 5, Onboarding.isDone { MagicPanel.keepMainWindowHidden() }
            urls.forEach(Store.shared.handle(url:))
        }
    }

    /// The Dock icon shows the desk whenever it isn't on screen: put away for an app's sidebar, minimized, or closed,
    /// whatever else of Lamp's is open (Settings, a chat panel, a preview), since the desk is where everything starts.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            if !LampWindows.deskShown { Store.shared.showDesk() }
        }
        return true
    }

    /// Closing Lamp's window quits it, except while an app's sidebar is open: Lamp is still in use there. A preview
    /// isn't Lamp's window: with the desk closed it's the last one AppKit counts (a chat is a panel, which it doesn't),
    /// and stopping the app it shows must leave Lamp running. Nor while the person chose to keep their phone apps
    /// opening and one is on a phone: Lamp stays to put it back before it stops opening (`PhoneRenewals`).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated {
            !previewClosed && !SidebarServer.shared.isInUse && !(PhoneRenewals.staysOpen && PhoneRenewals.anyOnPhones(Store.shared.projects))
        }
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
            Adb.stopServer()
        }
    }
}
