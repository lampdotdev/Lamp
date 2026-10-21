import SwiftUI

/// What a turn in progress says it's doing, worked out in one place for every place that shows it: the build card,
/// the line under a change in Lamp's window, the chat beside the app and the cover while the app reopens. Lamp keeps
/// one plain activity for the turn ("Thinking", "Working on the interface", "Building…"); what people read is that,
/// except while the model thinks or the wait itself is the news. A plain "Thinking" is the dullest thing the line can
/// say, and a model can think for a minute without a word, which one frozen word makes read as stuck, so a think is
/// told in phrases that turn over every few seconds and grow more reassuring the longer it goes; a build or an
/// update in place that runs long says so. Anything the agent is named as doing is shown as it is.
public enum Activity {
    /// The activity while the model thinks, before or between its steps.
    public static let thinking = "Thinking"

    /// How long each thinking phrase stays.
    public static let turnover: TimeInterval = 3.5

    /// The thinking phrases, from how long the think has gone on. Calm, a little playful, and short enough for the
    /// chat beside the app at its narrowest. None is a bare "Thinking": a short think, the few seconds after a look,
    /// shows only the first phrase it gets.
    static let thinkingPhrases: [(from: TimeInterval, phrases: [String])] = [
        (0, ["Rubbing the lamp", "Mulling it over", "Picturing it", "Turning it over"]),
        (20, ["Polishing the lamp", "Thinking it through", "Weighing a few ways", "Consulting the genie",
              "Getting the details right"]),
        (60, ["The genie is squinting", "Deep in thought", "The genie is concentrating", "Worth getting right",
              "Untangling the tricky part"]),
        (180, ["Still on it, nothing's stuck", "Big wishes take a few minutes", "The genie hasn't wandered off"]),
    ]

    /// What a build says once it has run a while.
    static let buildingLater: [(from: TimeInterval, words: String)] = [
        (30, "Still building…"), (90, "Taking a little longer…"),
    ]

    /// What putting a change into the open app says once it has run a while: its compile can take a minute or more.
    static let updatingLater: [(from: TimeInterval, words: String)] = [
        (30, "Still updating…"), (90, "Taking a little longer…"),
    ]

    static func isBuilding(_ activity: String) -> Bool { activity.hasPrefix("Building") }
    static func isUpdating(_ activity: String) -> Bool { activity.hasPrefix("Updating") && activity.hasSuffix("in place…") }

    /// The words for `activity` once it has gone on for `waited` seconds. `start` picks which phrase a think opens
    /// on, so a turn of many short thinks doesn't say the same one each time.
    public static func words(_ activity: String, waited: TimeInterval, start: Int = 0) -> String {
        if activity == thinking {
            // Phrases change only on the turnover's beat, a new tier included, so nothing changes twice in a moment.
            let beat = Int(max(0, waited) / turnover)
            let tier = thinkingPhrases.last { Double(beat) * turnover >= $0.from } ?? thinkingPhrases[0]
            let first = Int((tier.from / turnover).rounded(.up))
            return tier.phrases[(beat - first + abs(start % tier.phrases.count)) % tier.phrases.count]
        }
        if isBuilding(activity), let later = buildingLater.last(where: { waited >= $0.from }) { return later.words }
        if isUpdating(activity), let later = updatingLater.last(where: { waited >= $0.from }) { return later.words }
        return activity
    }

    /// How often the words for `activity` can change: on the thinking phrases' beat, every 30 seconds for a build
    /// or an update in place (their later wordings come at 30 and 90), never for anything else.
    static func period(of activity: String) -> TimeInterval? {
        activity == thinking ? turnover : isBuilding(activity) || isUpdating(activity) ? 30 : nil
    }
}

extension ChatLook {
    /// The activity's words as they are now (`Activity.words`), redrawn only when they change.
    public struct ActivityText: View {
        let activity: String
        let since: Date

        public init(_ activity: String, since: Date) {
            self.activity = activity
            self.since = since
        }

        public var body: some View {
            if let period = Activity.period(of: activity) {
                TimelineView(.periodic(from: since, by: period)) { context in words(at: context.date) }
            } else {
                words(at: since)
            }
        }

        private func words(at date: Date) -> some View {
            // A hair past the tick, which arithmetic on dates can land just short of.
            // The think's own start picks its first phrase, the same in every place that shows it.
            let text = Activity.words(activity, waited: date.timeIntervalSince(since) + 0.001,
                                      start: Int(since.timeIntervalSinceReferenceDate))
            return Text(text)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.35), value: text)
        }
    }
}
