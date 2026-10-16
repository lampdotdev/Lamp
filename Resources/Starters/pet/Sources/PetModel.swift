import SwiftUI

/// The pet and its day: what it ate, how full it is, its mood and its streak. Everything it keeps is one
/// `PetState`, saved to LampStore on every change.
@MainActor
final class PetModel: ObservableObject {
    @Published var state: PetState {
        didSet { LampStore.save(state, to: "pet") }
    }
    /// The clock the pet's mood is worked out from, moved on every half minute so hunger and bedtime show up
    /// without anything being tapped.
    @Published private(set) var now = Date()
    /// When the pet last ate and what, so its picture can bounce and show the food. Not saved.
    @Published private(set) var lastMeal: (at: Date, symbol: String)?

    private var clock: Timer?
    private let calendar = Calendar.current

    init() {
        var loaded = LampStore.load(PetState.self, from: "pet") ?? PetState()
        if !loaded.seeded {
            SampleData.seed(&loaded)
            loaded.seeded = true
        }
        state = loaded
        LampStore.save(state, to: "pet")
        startNewDayIfNeeded()
        updateReminder()

        // A tap on the reminder shows the pet.
        LampNotifications.onAction { _, _ in LampMenuBar.show() }
        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: How the pet is

    /// How full it is right now, from 0 to 1: what it was at its last meal, less what it has lost since.
    var fullness: Double {
        let hours = max(0, now.timeIntervalSince(state.fullnessAt) / 3600)
        return min(1, max(0, state.fullness - hours * PetRules.fullnessLostPerHour))
    }

    var mood: PetMood {
        let hour = calendar.component(.hour, from: now)
        if hour >= PetRules.bedtime || hour < PetRules.wakeUp { return .sleepy }
        if fullness >= PetRules.happyFrom { return .happy }
        if fullness < PetRules.hungryBelow { return .hungry }
        return .content
    }

    /// Happy days in a row, counting today once it's a happy one (so the streak never drops during a day
    /// that's still going).
    var streak: Int {
        let happyDays = Set(state.history.filter(\.wasHappy).map { calendar.startOfDay(for: $0.day) })
        var count = todaysResult.wasHappy ? 1 : 0
        var day = calendar.date(byAdding: .day, value: -1, to: state.day) ?? state.day
        while happyDays.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    /// The name to show, even while the person has emptied the name field to type a new one.
    var displayName: String {
        let name = state.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Your pet" : name
    }

    var accessory: PetAccessory { PetAccessory.forStreak(streak) }

    // MARK: Today's food

    func servingsEaten(of habit: Habit) -> Int {
        min(state.eaten[habit.id.uuidString] ?? 0, habit.timesPerDay)
    }

    func isDone(_ habit: Habit) -> Bool { servingsEaten(of: habit) >= habit.timesPerDay }

    var todaysResult: DayResult {
        DayResult(day: state.day,
                  servingsEaten: state.habits.reduce(0) { $0 + servingsEaten(of: $1) },
                  servingsGoal: state.habits.reduce(0) { $0 + $1.timesPerDay })
    }

    /// One serving's worth of fullness: enough that doing everything fills the pet from its morning level.
    private var fullnessPerServing: Double {
        let goal = max(1, todaysResult.servingsGoal)
        return max(PetRules.leastPerServing, (1 - PetRules.morningFullness) / Double(goal))
    }

    func feed(_ habit: Habit) {
        startNewDayIfNeeded()
        guard !isDone(habit) else { return }
        now = Date()
        let before = fullness
        state.eaten[habit.id.uuidString] = servingsEaten(of: habit) + 1
        state.fullness = min(1, before + fullnessPerServing)
        state.fullnessAt = now
        lastMeal = (now, habit.symbol)
        updateReminder()
    }

    /// Takes back the last serving of a habit, for a tap made by mistake.
    func unfeed(_ habit: Habit) {
        let eaten = servingsEaten(of: habit)
        guard eaten > 0 else { return }
        now = Date()
        let before = fullness
        state.eaten[habit.id.uuidString] = eaten - 1
        state.fullness = max(0, before - fullnessPerServing)
        state.fullnessAt = now
        updateReminder()
    }

    // MARK: Habits

    func addHabit() {
        state.habits.append(Habit(name: "New Habit", symbol: "star.fill"))
        updateReminder()
    }

    func deleteHabit(_ habit: Habit) {
        state.habits.removeAll { $0.id == habit.id }
        state.eaten[habit.id.uuidString] = nil
        updateReminder()
    }

    // MARK: Examples

    var hasExamples: Bool {
        state.habits.contains(where: \.isSample) || state.history.contains(where: \.isSample)
    }

    /// Removes the habits and the history the app came with, and nothing the person added.
    func clearExamples() {
        for habit in state.habits where habit.isSample { state.eaten[habit.id.uuidString] = nil }
        state.habits.removeAll(where: \.isSample)
        state.history.removeAll(where: \.isSample)
        updateReminder()
    }

    // MARK: Days and reminders

    private func tick() {
        now = Date()
        startNewDayIfNeeded()
    }

    /// At the first moment of a new day (or the first launch on one), yesterday is written into the history
    /// and the pet wakes up a little peckish. Days the app didn't run at all are simply missing, which ends a
    /// streak, as a day without food should.
    private func startNewDayIfNeeded() {
        let today = calendar.startOfDay(for: Date())
        guard today != state.day else { return }
        var next = state
        let finished = todaysResult
        if finished.servingsGoal > 0 { next.history.append(finished) }
        // A year is plenty for any streak the pet can show, and keeps the saved state small.
        if let cutoff = calendar.date(byAdding: .day, value: -400, to: today) {
            next.history.removeAll { $0.day < cutoff }
        }
        next.day = today
        next.eaten = [:]
        next.fullness = PetRules.morningFullness
        // Hunger starts counting at wake-up, so a pet whose day began at midnight isn't starving by breakfast.
        let wakeUp = calendar.date(bySettingHour: PetRules.wakeUp, minute: 0, second: 0, of: today) ?? today
        next.fullnessAt = max(Date(), wakeUp)
        state = next
        now = Date()
        updateReminder()
    }

    /// Keeps one gentle reminder waiting, when the person asked for it: this afternoon if the pet has had less
    /// than half its food by then, else tomorrow afternoon, which a meal tomorrow moves along again.
    func updateReminder() {
        let id = "hungry"
        let today = todaysResult
        guard state.remindersOn, today.servingsGoal > 0 else { return LampNotifications.cancel(id) }
        let now = Date()
        guard let thisAfternoon = calendar.date(bySettingHour: PetRules.reminderHour, minute: 0, second: 0, of: now),
              let tomorrowAfternoon = calendar.date(byAdding: .day, value: 1, to: thisAfternoon) else { return }
        let hungryToday = Double(today.servingsEaten) < Double(today.servingsGoal) / 2
        let when = now < thisAfternoon && hungryToday ? thisAfternoon : tomorrowAfternoon
        LampNotifications.send("\(displayName) is getting hungry",
                               body: "One of today's habits would cheer \(displayName) up.",
                               at: when, id: id)
    }
}
