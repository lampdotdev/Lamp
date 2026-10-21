import Foundation

/// Reads the inbox for school emails and turns each into the things it asks of the person. Two steps, so most mail
/// costs almost nothing: a quick yes or no on every new email (from its sender, subject and first lines), then the
/// whole text of the school ones, read for what to do.
@MainActor
enum MailReader {
    static func read(since: Date, settings: BackpackSettings, seen: LampStore.Collection<SeenEmail>, onList: [String],
                     status: (String) -> Void, learned: (String) -> Void) async throws -> [Todo] {
        guard await LampAI.isAvailable(.text) else {
            throw LampAI.Failure(message: "Reading emails needs AI set up in Lamp.", needsSetup: .text)
        }
        let messages = try await LampMail.inbox(limit: 500, since: since)
        let new = messages.filter { seen.get(key(for: $0)) == nil }
        guard !new.isEmpty else { return [] }

        status(new.count == 1 ? "Sorting 1 new email…" : "Sorting \(new.count) new emails…")
        let school = try await sort(new, settings: settings, learned: learned)
        let schoolKeys = Set(school.map(key(for:)))
        for message in new where !schoolKeys.contains(key(for: message)) {
            seen.put(SeenEmail(id: key(for: message), subject: message.subject, from: message.sender,
                               received: message.date, isSchool: false, found: 0))
        }

        // Oldest first, so a reminder email about something already found is recognised as one.
        var list = onList
        var found: [Todo] = []
        for (index, message) in school.sorted(by: { $0.date < $1.date }).enumerated() {
            status("Reading \(index + 1) of \(school.count) school emails…")
            do {
                let todos = try await todos(in: message, settings: settings, onList: list)
                found += todos
                list += todos.map(\.title)
                seen.put(SeenEmail(id: key(for: message), subject: message.subject, from: message.sender,
                                   received: message.date, isSchool: true, found: todos.count))
            } catch let failure as LampAI.Failure where failure.needsSetup != nil {
                throw failure
            } catch {
                // Not marked as read, so the next check tries this email again.
                print("Backpack couldn't read “\(message.subject)”: \(error.localizedDescription)")
            }
        }
        return found
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

    private static func sort(_ messages: [LampMail.Message], settings: BackpackSettings,
                             learned: (String) -> Void) async throws -> [LampMail.Message] {
        var school: [LampMail.Message] = []
        var unsure: [LampMail.Message] = []
        for message in messages {
            if Sender.matches(message.sender, any: settings.otherSenders) { continue }
            if Sender.matches(message.sender, any: settings.schoolSenders) { school.append(message) } else { unsure.append(message) }
        }
        guard !unsure.isEmpty else { return school }

        if await LampAI.isAvailable(.decisions) {
            let verdicts = try await LampAI.isTrue(question, each: unsure, remember: 30 * 86400) { message in
                ["from": message.sender, "subject": message.subject, "start": message.preview]
            }
            for verdict in verdicts {
                let probability = verdict.probability ?? 0
                if probability >= 0.6 { school.append(verdict.item) }
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
                let picked = try await LampAI.ask(question + " Answer for each email in the list. Reply with JSON: "
                                                  + "{\"school\": [the n of each email that is]}.",
                                                  data: json(listed), as: Picked.self)
                school += picked.school.filter { chunk.indices.contains($0) }.map { chunk[$0] }
            }
        }
        return school
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
        let body = (try? await LampMail.body(of: message.id)) ?? ""
        let email: [String: Any] = [
            "from": message.sender,
            "subject": message.subject,
            "received": LampAI.when(message.date),
            "children": settings.children,
            "already_on_list": onList,
            "body": String((body.isEmpty ? message.preview : body).prefix(8000)),
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
