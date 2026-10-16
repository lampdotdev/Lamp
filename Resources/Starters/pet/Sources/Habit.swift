import Foundation

/// Something the person does during the day, which the pet eats as food: each time it's done is one serving.
struct Habit: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// An SF Symbol, shown on the habit's button.
    var symbol: String
    /// How many servings make a full day of it ("Drink water" four times).
    var timesPerDay: Int = 1
    /// True for the habits the app came with, which Clear Examples removes.
    var isSample: Bool = false
}

extension Habit {
    /// The symbols offered when a habit is made or changed, grouped loosely by what they're for.
    static let symbolChoices = [
        "drop.fill", "cup.and.saucer.fill", "leaf.fill", "carrot.fill", "fork.knife",
        "figure.walk", "figure.run", "figure.cooldown", "figure.mind.and.body", "bicycle",
        "book.fill", "pencil", "brain.head.profile", "music.note", "paintbrush.fill",
        "bed.double.fill", "sun.max.fill", "moon.stars.fill", "pills.fill", "heart.fill",
        "phone.down.fill", "envelope.fill", "checkmark.circle.fill", "house.fill", "pawprint.fill",
    ]
}

/// How one finished day went, kept so the pet can count a streak of happy days.
struct DayResult: Codable, Hashable {
    /// The start of that day.
    var day: Date
    var servingsEaten: Int
    var servingsGoal: Int
    /// True for the made-up history the app came with, which Clear Examples removes.
    var isSample: Bool = false

    /// A day is a happy one when the pet got at least three quarters of its food, so one missed serving
    /// doesn't break a streak.
    var wasHappy: Bool {
        servingsGoal > 0 && Double(servingsEaten) >= Double(servingsGoal) * PetRules.happyDayShare
    }
}

/// Everything the app keeps, saved whole in LampStore under "pet".
struct PetState: Codable {
    var name = "Mochi"
    var habits: [Habit] = []
    /// The day `eaten` and `fullness` belong to (its start). A new day starts them over.
    var day = Calendar.current.startOfDay(for: Date())
    /// Servings eaten today, by habit id.
    var eaten: [String: Int] = [:]
    /// How full the pet was at `fullnessAt`, from 0 to 1; it falls slowly from there (`PetRules`).
    var fullness = PetRules.morningFullness
    var fullnessAt = Date()
    var history: [DayResult] = []
    var remindersOn = false
    /// The sample content is written once, on the first launch, and never again after it's cleared.
    var seeded = false
}
