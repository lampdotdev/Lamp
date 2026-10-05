import SwiftUI
import AppKit

@main
struct ForgeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        Window("Forge", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 480)
        }
        .commands {
            CheckForUpdatesCommand()
            CommandGroup(replacing: .newItem) {
                Button("New App") { store.create() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Button("Import Shared App…") { store.chooseImport() }
                    .keyboardShortcut("o")
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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Before launch finishes, so clicking a notification that launched Forge still opens its chat.
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { Notifier.shared.start() }
    }

    /// Generated apps call back with forge://edit?app=<slug> (⇧⌘E inside the app).
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            urls.forEach(Store.shared.handle(url:))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { LocalModels.shared.stopServer() }
    }
}
