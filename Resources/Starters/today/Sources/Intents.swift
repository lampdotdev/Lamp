import AppIntents

/// "Add a priority to Today" from Siri, Spotlight or Shortcuts, without opening the window.
struct AddPriorityIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Priority"
    static let description = IntentDescription("Adds a priority to today's list, if there's room.")

    @Parameter(title: "Priority")
    var priority: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let added = await MainActor.run { TodayModel.shared.addPriority(priority) }
        // Spelled out: before Xcode 26's SDK a dialog takes only a literal, not words put together.
        return .result(dialog: IntentDialog(stringLiteral: added ? "Added “\(priority)” to today." : "Today’s list is already full."))
    }
}

struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddPriorityIntent(),
                    phrases: ["Add a priority to \(.applicationName)", "Add to \(.applicationName)"],
                    shortTitle: "Add Priority",
                    systemImageName: "checklist")
    }
}
