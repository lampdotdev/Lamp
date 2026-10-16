import AppIntents

struct SongbookIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Guitar Songbook"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}
struct GuitarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent:SongbookIntent(),phrases:["Open my songbook in \(.applicationName)"],shortTitle:"Open Songbook",systemImageName:"guitars")
    }
}
