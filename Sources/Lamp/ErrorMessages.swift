/// Store and Provider use these same phrases that the bug reporter recognizes, so editing the
/// user-facing wording cannot silently disconnect it from the privacy-safe report summaries.
enum ErrorMessages {
    static let buildFailed = "Sorry, I couldn't get that change working. Try describing it differently, or press Undo."
    static let appDoesNotBuild = "This app doesn't build right now. Describe a change and I'll fix it, or press Undo."
    static let restoreFailed = "Lamp couldn't go back to how the app was before that message, so nothing was sent."
    static let providerBusy = "The AI is busy right now. Wait a minute and try again."
    static let localServerUnreachable = "Couldn't reach the local model server. Check Settings → Providers → Native Mac AI."

    static let openFailedPrefix = "Couldn't open the app: "
    static let installFailedPrefix = "Couldn't install the app: "
    static let aiFailedPrefix = "Something went wrong talking to the AI: "
    static let authenticationFailedSuffix = " key or sign-in didn't work. Check it in Lamp → Settings (⌘,)."
    static let quotaExceededSuffix = " account is out of credit or quota. Top it up, or pick another provider in Settings."
    static let crashAfterLaunchSuffix = " crashes when it opens. Ask me to fix the crash, or press Undo."
    static let quitsAfterLaunchSuffix = " still quits right after opening. Try describing the change differently, or press Undo."

    static func openFailed(_ detail: String) -> String { openFailedPrefix + detail }
    static func installFailed(_ detail: String) -> String { installFailedPrefix + detail }
    static func aiFailed(_ detail: String) -> String { aiFailedPrefix + detail }
    static func authenticationFailed(_ provider: String) -> String { "Your " + provider + authenticationFailedSuffix }
    static func quotaExceeded(_ provider: String) -> String { "Your " + provider + quotaExceededSuffix }
    static func crashAfterLaunch(_ app: String) -> String { app + crashAfterLaunchSuffix }
    static func quitsAfterLaunch(_ app: String) -> String { app + quitsAfterLaunchSuffix }
}
