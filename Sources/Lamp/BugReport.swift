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
        case setupOffered = "Setup offered"
    }

    static func errorSummary(_ message: String?) -> String {
        guard let message else { return "No error recorded." }
        switch message {
        case ErrorMessages.buildFailed, ErrorMessages.appDoesNotBuild:
            return "The app failed to build."
        case ErrorMessages.restoreFailed:
            return "Returning to an earlier version failed."
        case ErrorMessages.providerBusy:
            return "The AI provider rate-limited the request."
        case ErrorMessages.connectionFailed:
            return "The connection to the AI failed."
        case ErrorMessages.localServerUnreachable:
            return "The local model server could not be reached."
        default:
            if message.hasPrefix(ErrorMessages.openFailedPrefix) {
                return "The app could not be opened."
            }
            if message.hasPrefix(ErrorMessages.installFailedPrefix) {
                return "The app could not be installed."
            }
            if message.hasPrefix(ErrorMessages.aiFailedPrefix) {
                return "Communication with the AI failed."
            }
            if message.hasSuffix(ErrorMessages.authenticationFailedSuffix) {
                return "The AI key or sign-in did not work."
            }
            if message.hasSuffix(ErrorMessages.quotaExceededSuffix) {
                return "The AI account is out of credit or quota."
            }
            if message.hasSuffix(ErrorMessages.crashAfterLaunchSuffix) ||
                message.hasSuffix(ErrorMessages.quitsAfterLaunchSuffix) {
                return "The app quit unexpectedly after opening."
            }
            if message.hasSuffix(ErrorMessages.setAsideSuffix) {
                return "The app crashed as a change went into it, and the version before it was opened again."
            }
            if message.hasSuffix(ErrorMessages.crashedSuffix) {
                return "The app crashed again after Lamp tried to fix it."
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
