import Foundation

/// Only fixed labels leave the log. Scrubbing arbitrary error output cannot reliably remove keys,
/// prompts or source code, so unknown errors stay private until the person chooses to describe them.
enum BugReport {
    enum Activity: String, CaseIterable {
        case request = "Request"
        case reply = "Agent reply"
        case status = "Status update"
        case error = "Error"
        case detail = "Agent detail"
        case tool = "Tool call"
        case summary = "Work finished"
        case needsKey = "Key requested"
    }

    static func errorSummary(_ message: String?) -> String {
        guard let message else { return "No error recorded." }
        switch message {
        case "Sorry, I couldn't get that change working. Try describing it differently, or press Undo.",
             "This app doesn't build right now. Describe a change and I'll fix it, or press Undo.":
            return "The app failed to build."
        case "Lamp couldn't go back to how the app was before that message, so nothing was sent.":
            return "Returning to an earlier version failed."
        case "The AI is busy right now. Wait a minute and try again.":
            return "The AI provider rate-limited the request."
        case "Couldn't reach the local model server. Check Settings → Providers → Native Mac AI.":
            return "The local model server could not be reached."
        default:
            if message.hasPrefix("Couldn't open the app: ") {
                return "The app could not be opened."
            }
            if message.hasPrefix("Couldn't install the app: ") {
                return "The app could not be installed."
            }
            if message.hasPrefix("Something went wrong talking to the AI: ") {
                return "Communication with the AI failed."
            }
            if message.hasSuffix(" key or sign-in didn't work. Check it in Lamp → Settings (⌘,).") {
                return "The AI key or sign-in did not work."
            }
            if message.hasSuffix(" account is out of credit or quota. Top it up, or pick another provider in Settings.") {
                return "The AI account is out of credit or quota."
            }
            if message.hasSuffix(" crashes when it opens. Ask me to fix the crash, or press Undo.") ||
                message.hasSuffix(" still quits right after opening. Try describing the change differently, or press Undo.") {
                return "The app quit unexpectedly after opening."
            }
            return "An error was recorded; its message is omitted for privacy."
        }
    }

    static func draft(version: String, build: String, macOS: String, engine: String,
                      isDev: Bool, hasSelection: Bool, isBusy: Bool,
                      activity: [Activity], lastError: String?, capturedAt: Date = Date()) -> String {
        let recent = activity.suffix(20).map(\.rawValue).joined(separator: " → ")
        return """
        Lamp bug report

        What happened:


        Steps to reproduce:
        1.

        What I expected:


        Error message or other details I choose to share:


        Diagnostics
        Captured: \(capturedAt.ISO8601Format())
        Lamp version: \(version)
        Lamp build: \(build)
        Edition: \(isDev ? "Lamp Dev" : "Lamp")
        macOS: \(macOS)
        Engine selected in Settings: \(engine)
        Engine when the problem happened (if different):
        App selected: \(hasSelection ? "Yes" : "No")
        Work in progress: \(isBusy ? "Yes" : "No")
        Last error in the selected app: \(hasSelection ? errorSummary(lastError) : "No app selected.")
        Recent activity in the selected app (up to 20 entries, oldest first, labels only):
        \(recent.isEmpty ? "No recent activity." : recent)

        Automatic diagnostics contain no log text, keys, chat content, app names, paths or app code.
        """
    }
}
