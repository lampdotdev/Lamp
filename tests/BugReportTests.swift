import Foundation

@main
struct BugReportTests {
    static func main() {
        func draft(activity: [BugReport.Activity] = [], error: String? = nil,
                   selected: Bool = true, busy: Bool = false, dev: Bool = false,
                   engine: String = "Built-in agent (pi)") -> String {
            BugReport.draft(version: "0.9.0", build: "0.9.0.12", macOS: "26.6.2", engine: engine,
                            isDev: dev, hasSelection: selected, isBusy: busy,
                            activity: activity, lastError: error, capturedAt: Date(timeIntervalSince1970: 0))
        }
        let metadata = draft()
        for expected in ["Lamp version: 0.9.0", "Lamp build: 0.9.0.12", "macOS: 26.6.2",
                         "Edition: Lamp", "Captured: 1970-01-01T00:00:00Z",
                         "Engine selected in Settings: Built-in agent (pi)",
                         "No error recorded.", "No recent activity.", "What happened:",
                         "Steps to reproduce:", "What I expected:"] {
            precondition(metadata.contains(expected), "Missing \(expected)")
        }
        for engine in ["Claude Code", "Codex"] {
            precondition(draft(engine: engine).contains("Engine selected in Settings: \(engine)"))
        }
        precondition(draft(selected: false).contains("Last error in the selected app: No app selected."))
        precondition(draft(busy: true, dev: true).contains("Work in progress: Yes"))
        precondition(draft(dev: true).contains("Edition: Lamp Dev"))

        let privateMessages = [
            "sk-or-v1-private-key Authorization: Bearer private-token",
            "Something went wrong talking to the AI: My confidential chat and app source code",
            "Couldn't open the app: /Users/private/Clients/Secret.swift",
            "The AI is busy right now. Wait a minute and try again.\nPRIVATE_PAYLOAD",
            "-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----",
            "api_key=unfamiliar-secret-format password=hunter2"
        ]
        for message in privateMessages {
            let report = draft(activity: BugReport.Activity.allCases, error: message)
            precondition(!report.contains(message), "Raw error leaked")
            precondition(!report.contains("PRIVATE_PAYLOAD") && !report.contains("Secret.swift"))
        }
        precondition(BugReport.errorSummary("unrecognized private text") == "An error was recorded; its message is omitted for privacy.")
        precondition(BugReport.errorSummary("Couldn't open the app: /Users/private/secret") == "The app could not be opened.")
        precondition(BugReport.errorSummary("Something went wrong talking to the AI: secret") == "Communication with the AI failed.")
        precondition(BugReport.errorSummary("Secret App crashes when it opens. Ask me to fix the crash, or press Undo.") == "The app quit unexpectedly after opening.")
        precondition(BugReport.errorSummary("Your OpenRouter key or sign-in didn't work. Check it in Lamp → Settings (⌘,).") == "The AI key or sign-in did not work.")
        precondition(BugReport.errorSummary("Sorry, I couldn't get that change working. Try describing it differently, or press Undo.") == "The app failed to build.")
        precondition(BugReport.errorSummary("The AI is busy right now. Wait a minute and try again.") == "The AI provider rate-limited the request.")
        precondition(BugReport.errorSummary("Couldn't reach the local model server. Check Settings → Providers → Native Mac AI.") == "The local model server could not be reached.")
        precondition(BugReport.errorSummary("Lamp couldn't go back to how the app was before that message, so nothing was sent.") == "Returning to an earlier version failed.")

        let bounded = draft(activity: [.request] + Array(repeating: .tool, count: 19) + [.error])
        let sequence = bounded.components(separatedBy: "labels only):\n")[1].components(separatedBy: "\n")[0]
        precondition(sequence.components(separatedBy: " → ").count == 20)
        precondition(!sequence.contains("Request"))
        precondition(sequence.hasSuffix("Tool call → Error"))
        print("PASS: versions, all engines, empty/selected/busy states, bounded activity, safe error classification and private payload exclusion")
    }
}
