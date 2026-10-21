import SwiftUI

/// The one model: the list, the settings, and checking Mail every so often once the person has asked it to.
@MainActor
final class Backpack: ObservableObject {
    static let shared = Backpack()

    @Published private(set) var todos: [Todo] = []
    @Published var settings: BackpackSettings {
        didSet { if settings != oldValue { LampStore.save(settings, to: "settings") } }
    }
    @Published private(set) var lastChecked: Date?
    /// What a check is doing now ("Reading 3 of 12 school emails…"), nil when none is under way.
    @Published private(set) var status: String?
    @Published private(set) var error: String?

    private let saved = LampStore.collection("todos", of: Todo.self)
    let seen = LampStore.collection("emails", of: SeenEmail.self)
    private var schedule: LampSchedule?

    private init() {
        settings = LampStore.load(BackpackSettings.self, from: "settings") ?? BackpackSettings()
        lastChecked = LampStore.load(Date?.self, from: "lastChecked") ?? nil
        Examples.addOnce(to: saved)
        todos = saved.all()
        LampNotifications.onAction { _, _ in LampWindows.show() }
        schedule = LampSchedule.every("mail", minutes: 15) {
            await Backpack.shared.checkIfReading()
        }
    }

    // MARK: What the panel shows

    var open: [Todo] { todos.filter { !$0.isDone } }
    var hasExamples: Bool { todos.contains { $0.isExample == true } }
    var isChecking: Bool { status != nil }

    /// What needs doing in the next three days, late things included: the count beside the menu bar icon.
    var soon: Int {
        let horizon = Calendar.current.startOfDay(for: .now).addingTimeInterval(3 * 86400)
        return open.filter { ($0.due ?? .distantFuture) < horizon }.count
    }

    struct Group: Identifiable {
        let id: String
        let title: String
        let todos: [Todo]
    }

    var groups: [Group] {
        let today = Calendar.current.startOfDay(for: .now)
        let week = today.addingTimeInterval(7 * 86400)
        let byDue = open.sorted { ($0.due ?? .distantFuture, $0.received) < ($1.due ?? .distantFuture, $1.received) }
        let late = byDue.filter { ($0.due ?? .distantFuture) < today }
        let thisWeek = byDue.filter { guard let due = $0.due else { return false }; return due >= today && due < week }
        let later = byDue.filter { ($0.due ?? .distantPast) >= week }
        let whenever = open.filter { $0.due == nil }.sorted { $0.received > $1.received }
        return [Group(id: "late", title: "Late", todos: late),
                Group(id: "week", title: "This Week", todos: thisWeek),
                Group(id: "later", title: "Coming Up", todos: later),
                Group(id: "whenever", title: "No Date", todos: whenever)].filter { !$0.todos.isEmpty }
    }

    /// Done in the last two weeks, newest first.
    var recentlyDone: [Todo] {
        let since = Date.now.addingTimeInterval(-14 * 86400)
        return todos.filter { ($0.done ?? .distantPast) > since }.sorted { $0.done! > $1.done! }
    }

    // MARK: Changing the list

    func toggle(_ todo: Todo) {
        var todo = todo
        todo.done = todo.isDone ? nil : .now
        put(todo)
        // Ticking it off here ticks it off in Reminders too.
        if todo.isDone, let id = todo.reminderID { Task { try? await LampReminders.complete(id) } }
    }

    func delete(_ todo: Todo) {
        saved.delete(todo.id)
        todos.removeAll { $0.id == todo.id }
    }

    func put(_ todo: Todo) {
        saved.put(todo)
        if let index = todos.firstIndex(where: { $0.id == todo.id }) { todos[index] = todo } else { todos.append(todo) }
    }

    func addToReminders(_ todo: Todo) async {
        do {
            var todo = todo
            todo.reminderID = try await LampReminders.add(todo.title, due: todo.due, notes: notes(for: todo))
            put(todo)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addToCalendar(_ todo: Todo) async {
        guard let due = todo.due else { return }
        do {
            var todo = todo
            let start = todo.hasTime ? due : Calendar.current.startOfDay(for: due)
            let end = todo.hasTime ? due.addingTimeInterval(3600) : start.addingTimeInterval(86400)
            todo.eventID = try await LampCalendar.add(todo.title, start: start, end: end, notes: notes(for: todo), allDay: !todo.hasTime)
            put(todo)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func notes(for todo: Todo) -> String {
        var lines = ["From \(Sender.name(todo.from)): \(todo.subject)"]
        if let quote = todo.quote { lines.append("“\(quote)”") }
        return lines.joined(separator: "\n")
    }

    func clearExamples() {
        for todo in todos where todo.isExample == true { saved.delete(todo.id) }
        todos.removeAll { $0.isExample == true }
    }

    /// Forgets every email read and everything found in them, and reads the look-back again.
    func startOver() async {
        saved.deleteAll()
        seen.deleteAll()
        todos = []
        lastChecked = nil
        LampStore.save(lastChecked, to: "lastChecked")
        await check()
    }

    // MARK: Reading Mail

    /// The first look, from the panel's button: the last weeks of the inbox are read, and once that worked the
    /// examples go and Mail is checked from then on. A read that fails leaves the examples and the button, with
    /// why it stopped, so the person isn't told there's nothing to do when nothing was read.
    func startReading() async {
        await check()
        guard error == nil, lastChecked != nil else { return }
        clearExamples()
        settings.readsMail = true
    }

    func checkIfReading() async {
        guard settings.readsMail else { return }
        await check()
    }

    func check() async {
        guard !isChecking else { return }
        error = nil
        status = "Looking through Mail…"
        defer { status = nil }
        let firstLook = lastChecked == nil
        // A day's overlap, so mail that arrived while the last check ran isn't missed; what's been read is skipped.
        let since = lastChecked?.addingTimeInterval(-86400) ?? Date.now.addingTimeInterval(-Double(settings.lookBackDays) * 86400)
        do {
            let found = try await MailReader.read(since: since, settings: settings, seen: seen, onList: open.map(\.title)) { [weak self] status in
                self?.status = status
            } learned: { [weak self] sender in
                guard let self, !Sender.matches(sender, any: settings.schoolSenders) else { return }
                settings.schoolSenders.append(Sender.address(sender))
            }
            for todo in found { put(todo) }
            lastChecked = .now
            LampStore.save(lastChecked, to: "lastChecked")
            if !firstLook, settings.notify, !found.isEmpty { announce(found) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func announce(_ found: [Todo]) {
        let first = found[0]
        let title = found.count == 1 ? first.title : "\(found.count) new things from school"
        let body = found.count == 1
            ? [Format.due(first), "from \(Sender.name(first.from))"].compactMap { $0 }.joined(separator: ", ")
            : found.prefix(3).map(\.title).joined(separator: " · ")
        LampNotifications.send(title, body: body)
    }
}
