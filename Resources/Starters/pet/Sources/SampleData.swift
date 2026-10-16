import Foundation

/// What the app comes with on its first launch: four everyday habits and four happy days behind it, so the
/// pet already has a streak and a flower to show. All of it is marked `isSample`, which is what Clear
/// Examples removes.
enum SampleData {
    static func seed(_ state: inout PetState) {
        let water = Habit(name: "Drink water", symbol: "drop.fill", timesPerDay: 4, isSample: true)
        let stretch = Habit(name: "Stretch", symbol: "figure.cooldown", isSample: true)
        let read = Habit(name: "Read 10 pages", symbol: "book.fill", isSample: true)
        let walk = Habit(name: "Walk", symbol: "figure.walk", isSample: true)
        state.habits = [water, stretch, read, walk]

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let goal = state.habits.reduce(0) { $0 + $1.timesPerDay }
        // Four good days before today, one of them a serving short, which still counts as happy.
        let eatenByDaysAgo = [1: goal, 2: goal - 1, 3: goal, 4: goal]
        state.history = eatenByDaysAgo.sorted { $0.key > $1.key }.compactMap { daysAgo, eaten in
            calendar.date(byAdding: .day, value: -daysAgo, to: today).map {
                DayResult(day: $0, servingsEaten: eaten, servingsGoal: goal, isSample: true)
            }
        }

        // Today has started with a glass of water, so the pet is content rather than hungry.
        state.day = today
        state.eaten = [water.id.uuidString: 1]
        state.fullness = 0.55
        state.fullnessAt = Date()
    }
}
