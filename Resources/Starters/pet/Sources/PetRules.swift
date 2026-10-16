import Foundation

/// The numbers that decide how the pet feels, in one place so they're easy to tune.
enum PetRules {
    /// How full the pet wakes up each morning: a little peckish.
    static let morningFullness = 0.35
    /// How much fullness it loses each hour, so an unfed pet gets hungry by the afternoon.
    static let fullnessLostPerHour = 0.05
    /// The least one serving fills it, so a day with many servings still feels rewarding per tap.
    static let leastPerServing = 0.12
    /// Share of the day's servings that makes it a happy day for the streak.
    static let happyDayShare = 0.75
    /// At or above this the pet is happy; below `hungryBelow` it's hungry; in between, content.
    static let happyFrom = 0.7
    static let hungryBelow = 0.3
    /// The pet sleeps from `bedtime` until `wakeUp` (hours of the day).
    static let bedtime = 22
    static let wakeUp = 7
    /// When the optional reminder comes, if the pet has had less than half its food by then.
    static let reminderHour = 15
}
