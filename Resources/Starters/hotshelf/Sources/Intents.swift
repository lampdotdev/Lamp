import AppIntents

struct PickSauceIntent: AppIntent {
    static let title: LocalizedStringResource = "Pick a Hot Sauce"
    static let description = IntentDescription("Picks the bottle from your shelf that suits what you're cooking.")

    @Parameter(title: "Dish", requestValueDialog: "What are you cooking?")
    var dish: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let pick = try await Shelf.shared.choose(for: dish)
        let name = Shelf.shared.bottle(pick.bottleID)?.name ?? "that one"
        return .result(dialog: "\(name). \(pick.why)")
    }
}

struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PickSauceIntent(),
                    phrases: ["Pick a hot sauce with \(.applicationName)", "Which hot sauce tonight in \(.applicationName)"],
                    shortTitle: "Pick a Hot Sauce",
                    systemImageName: "flame")
    }
}
