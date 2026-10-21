import Foundation

/// Reads the inbox for school emails and turns each into the things it asks of the person. Two steps, so most mail
/// costs almost nothing: a quick yes or no on every new email (from its sender, subject and first lines), then the
/// whole text of the school ones, read for what to do.
///
/// Nothing is lost to a failure on the way: mail is read a week at a time, oldest first (a busy week in smaller
/// pieces, since Mail hands back only so many at once); an email is marked read only once it's been judged and what
/// it asks for is saved; and what comes back is how far the inbox has been read without a gap, so the next check
/// starts from the first email that couldn't be read.
@MainActor
enum MailReader {
    /// The most emails asked of Mail at once. A stretch that fills it is read again in halves.
    private static let batch = 200

    /// Reads everything received from `start` on and returns how far it got: everything received before that date
    /// has been read, or was there and couldn't be and will be tried again from there.
    static func read(from start: Date, settings: BackpackSettings, seen: LampStore.Collection<SeenEmail>, onList: [String],
                     status: (String) -> Void, learned: (String) -> Void, keep: ([Todo]) -> Void) async throws -> Date {
        guard await LampAI.isAvailable(.text) else {
            throw LampAI.Failure(message: "Reading emails needs AI set up in Lamp.", needsSetup: .text)
        }
        let now = Date.now
        var windows: [(from: Date, to: Date)] = []
        var day = start
        while day < now {
            let next = min(day.addingTimeInterval(7 * 86400), now)
            windows.append((day, next))
            day = next
        }

        var list = onList
        var gap: Date?
        var tally = Tally()
        while !windows.isEmpty {
            let window = windows.removeFirst()
            status("Looking through mail from \(window.from.formatted(.dateTime.month(.abbreviated).day()))…")
            let messages = try await LampMail.inbox(limit: batch, since: window.from, before: window.to)
            let full = messages.count >= batch
            if full && window.to.timeIntervalSince(window.from) > 3600 {
                let middle = window.from.addingTimeInterval(window.to.timeIntervalSince(window.from) / 2)
                windows.insert(contentsOf: [(window.from, middle), (middle, window.to)], at: 0)
                continue
            }
            // An hour with more mail than one batch is drained from its newest end: each batch is followed by the
            // one before its oldest email, until a batch is short. Only a second holding a whole batch of mail
            // can't be got past, and is left to try again from there.
            var batchOfMail = messages
            var before = window.to
            while true {
                let whole = try await process(batchOfMail, settings: settings, seen: seen, list: &list, tally: &tally,
                                              status: status, learned: learned, keep: keep)
                if !whole { gap = gap ?? window.from }
                guard batchOfMail.count >= batch else { break }
                // Up to and including the oldest one's second, so mail in that second isn't skipped; what's been
                // read in it is passed over.
                guard let oldest = batchOfMail.map(\.date).min(), oldest.addingTimeInterval(1) < before else {
                    gap = gap ?? window.from
                    break
                }
                before = oldest.addingTimeInterval(1)
                batchOfMail = try await LampMail.inbox(limit: batch, since: window.from, before: before)
            }
        }
        // Nothing judged or read at all is a check that didn't happen (the AI unreachable, say), not an inbox
        // with nothing in it: it says so, and a first read keeps its examples.
        if tally.missed > 0 && tally.read == 0 {
            throw LampAI.Failure(message: tally.missed == 1 ? "Backpack couldn't read the new email. It'll try again."
                                 : "Backpack couldn't read the \(tally.missed) new emails. It'll try again.")
        }
        return gap ?? now
    }

    /// How many new emails a check got through, and how many it couldn't.
    private struct Tally {
        var read = 0
        var missed = 0
    }

    /// Judges and reads the emails not read before. False when some couldn't be, which are left to try again.
    private static func process(_ messages: [LampMail.Message], settings: BackpackSettings, seen: LampStore.Collection<SeenEmail>,
                                list: inout [String], tally: inout Tally, status: (String) -> Void, learned: (String) -> Void,
                                keep: ([Todo]) -> Void) async throws -> Bool {
        let new = messages.filter { seen.get(key(for: $0)) == nil }
        guard !new.isEmpty else { return true }

        status(new.count == 1 ? "Sorting 1 new email…" : "Sorting \(new.count) new emails…")
        let sorted = try await sort(new, settings: settings, learned: learned)
        tally.read += sorted.other.count
        tally.missed += sorted.unjudged.count
        for message in sorted.other {
            seen.put(SeenEmail(id: key(for: message), subject: message.subject, from: message.sender,
                               received: message.date, isSchool: false, found: 0))
        }

        // Oldest first, so a reminder email about something already found is recognised as one.
        var whole = sorted.unjudged.isEmpty
        let school = sorted.school.sorted { $0.date < $1.date }
        for (index, message) in school.enumerated() {
            status("Reading \(index + 1) of \(school.count) school emails…")
            do {
                let todos = try await todos(in: message, settings: settings, onList: list)
                // What it asks for is saved before the email is marked read, so a quit or a failure between the
                // two leaves the email to be read again rather than its todos lost.
                keep(todos)
                list += todos.map(\.title)
                seen.put(SeenEmail(id: key(for: message), subject: message.subject, from: message.sender,
                                   received: message.date, isSchool: true, found: todos.count))
                tally.read += 1
            } catch let failure as LampAI.Failure where failure.needsSetup != nil {
                throw failure
            } catch {
                whole = false
                tally.missed += 1
                print("Backpack couldn't read “\(message.subject)”: \(error.localizedDescription)")
            }
        }
        return whole
    }

    /// The same email gets the same key however often it's listed.
    static func key(for message: LampMail.Message) -> String {
        "\(message.id)-\(Int(message.date.timeIntervalSince1970))"
    }

    // MARK: Which emails are from school

    private static let question = """
        Is this email from a child's school, teacher, class, school district, PTA or after-school program, \
        about that child's schooling?
        """

    private struct Sorted {
        var school: [LampMail.Message] = []
        var other: [LampMail.Message] = []
        /// Couldn't be judged this time (a timeout, a refusal): neither, and not marked read.
        var unjudged: [LampMail.Message] = []
    }

    private static func sort(_ messages: [LampMail.Message], settings: BackpackSettings,
                             learned: (String) -> Void) async throws -> Sorted {
        var sorted = Sorted()
        var unsure: [LampMail.Message] = []
        for message in messages {
            if Sender.matches(message.sender, any: settings.otherSenders) { sorted.other.append(message); continue }
            if Sender.matches(message.sender, any: settings.schoolSenders) { sorted.school.append(message) } else { unsure.append(message) }
        }
        guard !unsure.isEmpty else { return sorted }

        if await LampAI.isAvailable(.decisions) {
            let verdicts = try await LampAI.isTrue(question, each: unsure, remember: 30 * 86400) { message in
                ["from": message.sender, "subject": message.subject, "start": message.preview]
            }
            for verdict in verdicts {
                guard let probability = verdict.probability else { sorted.unjudged.append(verdict.item); continue }
                if probability >= 0.6 { sorted.school.append(verdict.item) } else { sorted.other.append(verdict.item) }
                // A sender it's sure of is remembered, and shown in Settings where it can be taken out.
                if probability >= 0.9 { learned(verdict.item.sender) }
            }
        } else {
            // No decision model: the text AI picks them out, many emails to a request.
            struct Picked: Decodable { let school: [Int] }
            for start in stride(from: 0, to: unsure.count, by: 40) {
                let chunk = Array(unsure[start..<min(start + 40, unsure.count)])
                let listed = chunk.enumerated().map { ["n": $0.offset, "from": $0.element.sender, "subject": $0.element.subject,
                                                       "start": String($0.element.preview.prefix(160))] as [String: Any] }
                do {
                    let picked = try await LampAI.ask(question + " Answer for each email in the list. Reply with JSON: "
                                                      + "{\"school\": [the n of each email that is]}.",
                                                      data: json(listed), as: Picked.self)
                    let chosen = Set(picked.school)
                    for (n, message) in chunk.enumerated() {
                        if chosen.contains(n) { sorted.school.append(message) } else { sorted.other.append(message) }
                    }
                } catch let failure as LampAI.Failure where failure.needsSetup != nil {
                    throw failure
                } catch {
                    sorted.unjudged += chunk
                }
            }
        }
        return sorted
    }

    // MARK: What a school email asks for

    private struct Found: Decodable {
        var items: [Item]
        struct Item: Decodable {
            var title: String
            var kind: String?
            var due: Date?
            var has_time: Bool?
            var child: String?
            var quote: String?
        }
    }

    private static let instructions = """
        The data is an email a parent got from their child's school (or teacher, class, PTA, district). List what \
        the parent has to do or remember because of it: forms to sign or return, money to pay, things to bring or \
        wear, events and days off that change the usual routine, and tasks such as signing up for a slot. Leave out \
        general news, fundraising with no deadline, anything whose date has already passed, and anything that \
        matches an entry in already_on_list. Work out dates from when the email was received.

        Reply with JSON: {"items": [{"title": "a short instruction, at most 8 words, e.g. Sign the field trip form", \
        "kind": "form, pay, bring, event or task", "due": "ISO 8601 date, with a time only when the email gives \
        one, or null", "has_time": true or false, "child": "the child's first name when it's for one of them, or \
        null", "quote": "the sentence in the email it comes from, at most 25 words"}]}. An empty list when there's \
        nothing to do.
        """

    private static func todos(in message: LampMail.Message, settings: BackpackSettings, onList: [String]) async throws -> [Todo] {
        // The whole email or nothing: what it asks for may be past its first lines, so an email whose text Mail
        // can't give now is tried again later rather than read from its start.
        let body = try await LampMail.body(of: message.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw LampAI.Failure(message: "Mail didn't give the email's text.") }
        let email: [String: Any] = [
            "from": message.sender,
            "subject": message.subject,
            "received": LampAI.when(message.date),
            "children": settings.children,
            "already_on_list": onList,
            "body": String(body.prefix(8000)),
        ]
        let found = try await LampAI.ask(instructions, data: json(email), as: Found.self)
        // Something from weeks ago whose day has gone is done or missed either way.
        let gone = Calendar.current.startOfDay(for: .now).addingTimeInterval(-2 * 86400)
        return found.items.filter { ($0.due ?? .distantFuture) >= gone && !$0.title.isEmpty }.map { item in
            Todo(title: item.title, kind: item.kind.flatMap(Todo.Kind.init(rawValue:)) ?? .task, due: item.due,
                 hasTime: item.has_time ?? false, child: item.child, from: message.sender, subject: message.subject,
                 received: message.date, quote: item.quote, emailKey: key(for: message))
        }
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
