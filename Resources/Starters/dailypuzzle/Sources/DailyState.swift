import Foundation
import Observation

/// What the whole app shares: the history of solves, each game's state for today, and whether the history
/// sheet is open. The window and the menus both act on it.
@Observable final class DailyState {
    let history = History()
    let ladder: LadderGame
    var showingHistory = false

    init() {
        ladder = LadderGame(history: history)
    }

    /// Called when the date may have changed (the system says so, or the app comes back to the front), so a
    /// window left open overnight shows the new day's puzzles.
    func refreshDay() {
        ladder.refreshDay()
    }
}
