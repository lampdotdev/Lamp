/// Store and Provider use these same phrases that the bug reporter recognizes, so editing the
/// user-facing wording cannot silently disconnect it from the privacy-safe report summaries.
enum ErrorMessages {
    static let buildFailed = "Sorry, I couldn't get that change working. Try describing it differently, or press Undo."
    static let appDoesNotBuild = "This app doesn't build right now. Describe a change and I'll fix it, or press Undo."
    static let restoreFailed = "Lamp couldn't go back to how the app was before that message, so nothing was sent."
    static let providerBusy = "The AI is busy right now. Wait a minute and try again."
    static let localServerUnreachable = "Couldn't reach the local model server. Check Settings → AI Providers → Native Mac AI."

    static let openFailedPrefix = "Couldn't open the app: "
    static let installFailedPrefix = "Couldn't install the app: "
    static let aiFailedPrefix = "Something went wrong talking to the AI: "
    static let authenticationFailedSuffix = " key or sign-in didn't work. Check it in Lamp → Settings (⌘,)."
    static let quotaExceededSuffix = " account is out of credit or quota. Top it up, or pick another provider in Settings."
    static let crashAfterLaunchSuffix = " crashes when it opens. Ask me to fix the crash, or press Undo."
    static let quitsAfterLaunchSuffix = " still quits right after opening. Try describing the change differently, or press Undo."

    /// A turn's change that was made but couldn't be saved as a version.
    static let versionNotSaved = "Lamp couldn't save this change as a version. It's in your app, and your next change will save both."

    static func openFailed(_ detail: String) -> String { openFailedPrefix + detail }
    /// A build that found the app open, where the person chose to keep it open rather than lose what it held.
    static func stayedOpen(_ app: String) -> String { app + " stayed open, so it's still the earlier version. Close it to get the new one." }
    /// Beside Force Quit, for an app that was asked to quit and doesn't answer: what the click costs.
    static func notResponding(_ app: String) -> String { app + " isn't responding. Forcing it to quit loses anything unsaved in it." }
    static func notDeleted(_ app: String) -> String { app + " stayed open, so it wasn't deleted." }
    static func installFailed(_ detail: String) -> String { installFailedPrefix + detail }
    static func aiFailed(_ detail: String) -> String { aiFailedPrefix + detail }
    static func authenticationFailed(_ provider: String) -> String { "Your " + provider + authenticationFailedSuffix }
    static func quotaExceeded(_ provider: String) -> String { "Your " + provider + quotaExceededSuffix }
    static func crashAfterLaunch(_ app: String) -> String { app + crashAfterLaunchSuffix }
    static func quitsAfterLaunch(_ app: String) -> String { app + quitsAfterLaunchSuffix }
    /// A promise the app's checks still find broken at the end of a request. The promise is the person's own words.
    static func doesntWorkYet(_ promise: String) -> String { "This doesn't work yet: \(sentence(promise))" }
    static let couldntCheck = "Lamp couldn't check that the app works."
    /// A promise the app's check couldn't try on this Mac (it has no microphone, say).
    static func notTriedHere(_ promise: String) -> String { "Not tried on this Mac: \(sentence(promise))" }
    /// The app's main promise, given up on after its check failed.
    static func cantBeDone(_ promise: String) -> String { "This couldn't be done: \(sentence(promise))" }
    /// The main promise the agent changed to, often after asking the person.
    static func nowPromises(_ promise: String) -> String { "Now it promises: \(sentence(promise))" }
    private static func sentence(_ words: String) -> String {
        let words = words.trimmed
        return words.hasSuffix(".") ? words : words + "."
    }
}
