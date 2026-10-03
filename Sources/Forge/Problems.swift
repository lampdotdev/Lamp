import SwiftUI

/// Something that went wrong in an app while it was being used: it crashed, or printed an error. Forge shows
/// it in the app's chat with a button that asks the agent to fix it, so the user doesn't have to describe it.
struct AppProblem: Equatable {
    /// "Crashed at 1:12 AM", "Printed 2 errors".
    let title: String
    /// The reason, in one line.
    let detail: String
    /// What Fix this sends to the agent.
    let request: String
    /// Tells one problem from the next, for dismissing.
    let key: String
    let crashed: Bool
}

enum Problems {
    /// Lines that mean something broke: Swift's own, the helpers Forge gives every app, and SwiftUI's
    /// complaints about state.
    private static let signs = [
        "Fatal error", "Uncaught exception", "precondition failed", "ForgeStore:", "ForgeAI ", "SQL error",
        "Modifying state during view update", "Publishing changes from within view updates", "AttributeGraph: cycle detected",
    ]

    /// The problem with the current build, if there is one: a crash first, otherwise errors it printed.
    static func current(in project: ForgeProject) -> AppProblem? {
        if let crash = Runtime.latestCrash(of: project) {
            let lines = crash.summary.split(separator: "\n").map(String.init)
            // "Crashed at 1:12:03 AM: EXC_BAD_ACCESS (SIGSEGV)"
            let reason = lines.first?.split(separator: ": ", maxSplits: 1).last.map(String.init) ?? ""
            return AppProblem(
                title: "Crashed at \(crash.date.formatted(date: .omitted, time: .shortened))",
                // Swift says why in what the app printed ("Fatal error: Index out of range"); the report often doesn't.
                detail: errors(in: project).last { $0.contains("Fatal error") || $0.contains("Uncaught exception") }
                    ?? lines.dropFirst().first { !$0.hasPrefix("Calls that led") && !$0.hasPrefix("  ") } ?? reason,
                request: "The app crashed. Find the cause and fix it.",   // Forge adds the crash report itself
                key: "crash-\(crash.date.timeIntervalSince1970)", crashed: true)
        }
        let errors = errors(in: project)
        guard let last = errors.last else { return nil }
        return AppProblem(
            title: errors.count == 1 ? "Printed an error" : "Printed \(errors.count) errors",
            detail: last,
            request: "While I was using the app it printed " + (errors.count == 1 ? "this error" : "these errors") +
                ". Find the cause and fix it.\n\n" + errors.joined(separator: "\n"),
            key: "errors-\(errors.count)-\(errors.joined().replacing(#/\d+/#, with: "").prefix(200))", crashed: false)
    }

    /// The different errors the latest launch has printed, oldest first, at most five.
    private static func errors(in project: ForgeProject) -> [String] {
        guard let data = try? Data(contentsOf: Runtime.logURL(project)) else { return [] }
        var found: [String] = []
        for line in String(decoding: data.suffix(64_000), as: UTF8.self).split(separator: "\n") {
            guard isError(line) else { continue }
            // The same error printed again and again is one error. Its timestamp and numbers don't count.
            let text = String(line.prefix(300))
            let plain = text.replacing(#/\d+/#, with: "")
            if !found.contains(where: { $0.replacing(#/\d+/#, with: "") == plain }) { found.append(text) }
        }
        return Array(found.suffix(5))
    }

    private static func isError(_ line: Substring) -> Bool {
        if signs.contains(where: line.contains) { return true }
        // What the app's own code printed (system messages start with a date): "Error: …", "Export failed: …".
        guard line.firstMatch(of: #/^\d{4}-\d\d-\d\d /#) == nil else { return false }
        let lowered = line.lowercased()
        return lowered.contains("error") || lowered.contains("failed")
    }
}

/// Shown above the message box when the app has crashed or printed errors since it was built.
struct ProblemCard: View {
    let problem: AppProblem
    let onFix: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(problem.title).font(.headline)
                if !problem.detail.isEmpty {
                    Text(problem.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            Button("Fix this", action: onFix).buttonStyle(.borderedProminent)
            Button(action: onDismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Dismiss")
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.3)))
    }
}
