import AppIntents

struct RehearseWeddingIntent: AppIntent {
    static let title: LocalizedStringResource = "Rehearse Wedding Italian"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "Time for a little Italian for the wedding.")
    }
}
struct WeddingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RehearseWeddingIntent(), phrases: ["Practice Italian with \(.applicationName)"], shortTitle: "Wedding Italian", systemImageName: "wineglass")
    }
}
