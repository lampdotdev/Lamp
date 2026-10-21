import Foundation
import Observation

/// What the whole app shares: the history of solves, the day's paper and the crossword being played on it, and
/// which sheet is open. The window and the menus both act on it.
@Observable final class DailyState {
    let history = History()
    let delivery = Delivery()
    let crossword: CrosswordGame
    var showingHistory = false
    var showingPlace = false

    init() {
        crossword = CrosswordGame(history: history)
        if let edition = delivery.edition {
            crossword.open(edition)
            Reminder.schedule(for: edition.place, solvedToday: crossword.isSolved)
        }
        delivery.onDelivery = { [crossword] edition in
            crossword.open(edition)
            Reminder.schedule(for: edition.place, solvedToday: crossword.isSolved)
        }
        delivery.canReword = { [crossword] in !crossword.hasStarted }
        crossword.onSolve = { solve in Reminder.schedule(for: solve.place ?? "Local", solvedToday: true) }
    }

    /// Called when the date may have changed (the system says so, or the app comes back to the front), so a
    /// window left open overnight shows the new day's paper.
    func refreshDay() {
        delivery.refreshDay()
    }
}
