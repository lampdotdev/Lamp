import Foundation

/// What a wish's shell commands may have downloaded, and the check that a later command asks before it runs one.
///
/// The judgment of one command (`CommandRisk`) can't see where its files came from: `chmod +x data/codec-data.bin` and
/// `./data/codec-data.bin` read as work on the app's own files, though an earlier `curl` fetched that file. So each
/// command that fetches from the internet is written down here before it runs, as the agent wrote it, and every later
/// command of the wish is asked, with those commands in front of the decision model, whether it runs, loads or makes
/// executable something they saved. A yes is Lamp's card, whichever engine runs the command.
///
/// Recorded before the command runs, never from what comes back afterwards: the next command can't start before
/// the record is written, and a command that fails, is cancelled or leaves something running in the background is
/// on it all the same. A command that copies, moves, links, unpacks or decodes what an earlier one fetched is written
/// down the same way, so a renamed copy is still one of the downloads. Nothing reads a command's text for paths or
/// looks at the disk: the decision model reads the commands. That is the limit: it is a check the model makes, not a
/// record of files, so a chain it doesn't connect (a copy it misreads, a download it doesn't recognize as one) runs.
///
/// Whatever can't be decided counts as fetched: a command the model gave no answer for is recorded, and a later
/// command checked against a record while the model can't answer gets the card. Nothing is dropped for being old
/// or for there being many: past `batch` records the check is put in several parts, each over all of its records.
/// A wish that is deleted leaves its records to every other wish (`retire`), since what it fetched may still be in
/// a shared folder such as /tmp.
enum Fetched {
    struct Record: Codable, Equatable {
        /// The command as the agent wrote it, cut to `commandLength`.
        var command: String
        var at: Date
        /// False when the model couldn't say whether it fetched anything, and it was written down to be safe.
        var sure: Bool
    }

    /// For tests, which keep theirs apart from any Lamp's.
    nonisolated(unsafe) static var folder = Edition.supportFolder.appendingPathComponent("Downloads")
    private static let lock = NSLock()
    /// Where a deleted wish's records go: every wish is checked against them.
    static let retired = "_deleted wishes"
    static let commandLength = 600
    /// Records put in front of the model at once.
    static let batch = 40

    // MARK: The record

    static func records(of wish: String) -> [Record] {
        lock.withLock { read(wish) }
    }

    /// The wish's own records and those every wish is checked against.
    static func checkedAgainst(for wish: String) -> [Record] {
        lock.withLock { read(wish) + read(retired) }
    }

    /// Writes one down. False when it couldn't be written, which the caller treats as a command that can't run.
    @discardableResult
    static func record(_ command: String, sure: Bool, for wish: String, at date: Date = Date()) -> Bool {
        lock.withLock {
            var all = read(wish)
            all.append(Record(command: String(command.prefix(commandLength)), at: date, sure: sure))
            return write(all, to: wish)
        }
    }

    /// The wish is gone: its records stay, for every other wish to be checked against.
    static func retire(_ wish: String) {
        lock.withLock {
            let own = read(wish)
            guard !own.isEmpty else { return }
            if write(read(retired) + own, to: retired) { try? FileManager.default.removeItem(at: file(wish)) }
        }
    }

    private static func file(_ wish: String) -> URL {
        folder.appendingPathComponent(String(wish.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == " " ? $0 : "_" }) + ".json")
    }

    private static func read(_ wish: String) -> [Record] {
        guard let data = try? Data(contentsOf: file(wish)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A file that can't be read is never taken as "nothing fetched": it stands for one unknown download.
        return (try? decoder.decode([Record].self, from: data))
            ?? [Record(command: "(Lamp couldn't read what this app's commands downloaded)", at: Date(), sure: false)]
    }

    private static func write(_ records: [Record], to wish: String) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return false }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return (try? data.write(to: file(wish), options: .atomic)) != nil
    }

    // MARK: The check

    /// What the check found about one command: whether it gets the card, and whether it is written down.
    struct Outcome: Equatable {
        /// It may run, load or make executable something an earlier command fetched (or the model couldn't say).
        var asks: Bool
        /// It may fetch from the internet, or copy or unpack what was fetched (or the model couldn't say).
        var records: Bool
        /// Whether the model answered every question.
        var sure: Bool
    }

    private static let yes = 0.5
    private static let no = 0.3

    static func questions(against records: Bool) -> [String: Any] {
        func noul(_ instructions: String, yes: String, no: String) -> [String: Any] {
            ["type": "noul", "instructions": instructions, "criteria": ["true": yes, "false": no]]
        }
        var questions: [String: Any] = [
            "fetches": noul(
                "Running `command` downloads or fetches anything from the internet and saves it on this Mac: a file, page, archive, program or repository (curl or wget to a file, a clone, a script that saves what it fetches). Printing a page without saving it is not saving.",
                yes: "Some part of the command saves something fetched from the internet.",
                no: "Nothing the command fetches is saved on this Mac."),
        ]
        if records {
            questions["derives"] = noul(
                "Running `command` copies, moves, renames, links, unpacks, decompresses or decodes a file that one of the commands in `earlier_downloads` could have saved, or one made from such a file.",
                yes: "Some part of the command makes a new file, name or link from something those commands may have saved.",
                no: "The command touches nothing those commands could have saved, or only reads it.")
            questions["runsFetched"] = noul(
                "Running `command` runs, executes, sources, opens, or loads as code or a library a file that one of the commands in `earlier_downloads` could have saved (or a copy, renamed file, link or unpacked file made from one), or makes such a file executable. Building the app's own code with its build tool is not this unless the command runs such a file itself. Reading, listing or measuring a file is not running it.",
                yes: "Some part of the command runs, loads or makes executable something those commands may have saved.",
                no: "Nothing those commands could have saved is run, loaded or made executable.")
        }
        return questions
    }

    static func state(command: String, folder: String, against records: [Record]) -> [String: Any] {
        var state: [String: Any] = ["command": command, "working_folder": "The app's own project folder: \(folder)"]
        if !records.isEmpty { state["earlier_downloads"] = records.map(\.command) }
        return state
    }

    /// The check, for every engine: `decide` is the decision model. With no records, the one question about fetching;
    /// with records, the three, once for each `batch` of them, all at once. Any part unanswered counts against the
    /// command: it is written down, and with records it gets the card.
    static func check(command: String, folder: String, against records: [Record],
                      decide: @escaping @Sendable (_ state: [String: Any], _ questions: [String: Any]) async throws -> [String: Any]) async -> Outcome {
        func noul(_ answers: [String: Any], _ id: String) -> Double? {
            guard let p = (answers[id] as? [String: Any])?["noul"] as? Double, (0...1).contains(p) else { return nil }
            return p
        }
        let groups = records.isEmpty ? [[]] : stride(from: 0, to: records.count, by: batch).map { Array(records[$0..<min($0 + batch, records.count)]) }
        let asked = questions(against: !records.isEmpty)
        let answers: [[String: Any]?] = await withTaskGroup(of: (Int, [String: Any]?).self) { group in
            for (index, part) in groups.enumerated() {
                let state = state(command: command, folder: folder, against: part)
                group.addTask { (index, try? await decide(state, asked)) }
            }
            var all = [[String: Any]?](repeating: nil, count: groups.count)
            for await (index, answer) in group { all[index] = answer }
            return all
        }
        var outcome = Outcome(asks: false, records: false, sure: true)
        for answer in answers {
            guard let answer, let fetches = noul(answer, "fetches") else {
                outcome = Outcome(asks: !records.isEmpty, records: true, sure: false)
                continue
            }
            if fetches > no { outcome.records = true }
            guard !records.isEmpty else { continue }
            guard let derives = noul(answer, "derives"), let runs = noul(answer, "runsFetched") else {
                outcome = Outcome(asks: true, records: true, sure: false)
                continue
            }
            if derives > no { outcome.records = true }
            if runs >= yes { outcome.asks = true }
        }
        return outcome
    }

    // MARK: In order

    /// One wish's checks one after the other, from the check to the record: a command is never checked before an
    /// earlier one that may have fetched something is written down.
    @MainActor final class Queue {
        private var tails: [String: Task<Void, Never>] = [:]

        func serially<T: Sendable>(_ key: String, _ body: @escaping @MainActor () async -> T) async -> T {
            let previous = tails[key]
            let work = Task { @MainActor () -> T in
                await previous?.value
                return await body()
            }
            tails[key] = Task { _ = await work.value }
            return await work.value
        }
    }

    /// The whole step for one command, in its wish's queue: the check; the card (`ask`) when it may run something
    /// fetched, else the rest of the approval (`decision`); and, when it may fetch and is allowed, the record, written
    /// before the answer goes back. `written` false: it had to be written down and couldn't be, so it doesn't run.
    struct Step: Equatable {
        var allowed: Bool
        var asked: Bool
        var written = true
    }

    @MainActor static func step(_ command: String, wish: String, folder: String, queue: Queue,
                                decide: @escaping @Sendable (_ state: [String: Any], _ questions: [String: Any]) async throws -> [String: Any],
                                ask: @escaping @MainActor () async -> Bool,
                                decision: @escaping @MainActor () async -> Bool) async -> Step {
        await queue.serially(wish) {
            let outcome = await check(command: command, folder: folder, against: checkedAgainst(for: wish), decide: decide)
            let allowed = outcome.asks ? await ask() : await decision()
            if allowed, outcome.records, !record(command, sure: outcome.sure, for: wish) {
                return Step(allowed: false, asked: outcome.asks, written: false)
            }
            return Step(allowed: allowed, asked: outcome.asks)
        }
    }
}
