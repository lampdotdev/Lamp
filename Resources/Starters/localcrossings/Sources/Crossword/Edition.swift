import Foundation
import Observation

/// Where the puzzles come from: where the person is (the system asks them once), or a place they typed.
enum PlaceChoice: Codable, Equatable {
    case here
    case named(String, latitude: Double, longitude: Double)
}

/// One day's paper: its puzzle, the place it was made for, and its number, counting the person's own editions.
struct Edition: Codable, Equatable {
    var day: Day
    var number: Int
    var place: String
    var latitude: Double
    var longitude: Double
    var puzzle: Crossword
}

/// Delivers each day's edition. Making one takes about half a second (the map's places, then the layout), and
/// once made it's kept, so the day's puzzle is the same until midnight wherever the Mac goes. The map's places
/// are kept too, for a few weeks or until the person is somewhere else, so later days don't ask again.
@Observable final class Delivery {
    enum Status: Equatable {
        case making
        /// The Mac didn't say where it is (refused, or Location Services off): the paper needs a place.
        case needsLocation
        case ready
        case failed(String)
    }

    private(set) var status: Status = .making
    private(set) var edition: Edition?
    /// Where the map behind the paper is centred: today's place, or the city in the Mac's time zone while the
    /// system asks where the Mac is.
    private(set) var backdrop: (latitude: Double, longitude: Double)?
    /// Told when a new edition arrives, or today's clues were reworded before any letter went in.
    var onDelivery: ((Edition) -> Void)?

    private(set) var choice: PlaceChoice = LampStore.load(PlaceChoice.self, from: "place") ?? .here

    init() {
        if let kept = LampStore.load(Edition.self, from: "edition"), kept.day == .today {
            edition = kept
            backdrop = (kept.latitude, kept.longitude)
            status = .ready
        } else {
            // While the system asks where the Mac is, the paper shows the city in its time zone.
            if edition == nil, choice == .here { Task { await showTimeZoneCity() } }
            Task { await deliver() }
        }
    }

    /// Change Place: a typed place, or back to where the Mac is.
    func choose(_ choice: PlaceChoice) {
        self.choice = choice
        LampStore.save(choice, to: "place")
        Task { await deliver(again: true) }
    }

    /// Called when the date may have changed, so a window left open overnight gets the new day's paper, and when
    /// the app comes back to the front, which is when someone who just allowed location in System Settings returns.
    func refreshDay() {
        if status == .needsLocation {
            Task { await deliver() }
            return
        }
        guard status != .making, edition?.day != .today else { return }
        Task { await deliver() }
    }

    func tryAgain() {
        Task { await deliver(again: edition?.day == .today) }
    }

    // MARK: Making an edition

    /// Counts deliveries begun, so one overtaken by a newer one (the person chose another place while the map
    /// was still answering) changes nothing when it finishes.
    private var deliveries = 0

    @MainActor private func deliver(again: Bool = false) async {
        deliveries += 1
        let this = deliveries
        let wanted = choice
        status = .making
        do {
            let spot = try await whereToMake(wanted)
            guard this == deliveries else { return }
            backdrop = (spot.latitude, spot.longitude)
            var place: Neighborhood
            if let kept = LampStore.load(Neighborhood.self, from: "neighborhood"), kept.covers(spot.latitude, spot.longitude) {
                place = kept
            } else {
                place = try await Survey.gather(latitude: spot.latitude, longitude: spot.longitude)
                guard this == deliveries else { return }
                LampStore.save(place, to: "neighborhood")
            }
            // A place the person named is called what they called it: the map often knows only the borough.
            if case .named(let name, _, _) = wanted { place.area = name }
            let plain = Answers.candidates(for: place)
            let curated = Answers.curated(place, from: plain)
            let pool = curated.count >= 12 ? curated : plain
            // Leaving out the last few days' answers can leave a small place too few to cross: then they come back.
            guard let puzzle = Layout.make(from: fresh(pool), seed: seed(for: place))
                    ?? Layout.make(from: pool, seed: seed(for: place)) else {
                throw Survey.TooQuiet()
            }
            // A new day counts as a new edition; a puzzle made again the same day (another place) keeps its number.
            let count = LampStore.load(Int.self, from: "editions") ?? 0
            let isNewDay = edition?.day != .today
            let made = Edition(day: .today, number: isNewDay ? count + 1 : max(count, 1), place: place.title,
                               latitude: place.latitude, longitude: place.longitude, puzzle: puzzle)
            if isNewDay { LampStore.save(count + 1, to: "editions") }
            keep(made)
            if place.curated.isEmpty { Task { await polish(place, plain) } }
        } catch is LocationRefused {
            if this == deliveries { status = .needsLocation }
        } catch {
            if this == deliveries { status = .failed(error.localizedDescription) }
        }
    }

    private struct LocationRefused: Error {}

    /// The spot to make today's paper for.
    @MainActor private func whereToMake(_ choice: PlaceChoice) async throws -> (latitude: Double, longitude: Double) {
        switch choice {
        case .here:
            guard await LampLocation.authorize() else { throw LocationRefused() }
            let here = try await LampLocation.current()
            return (here.latitude, here.longitude)
        case .named(_, let latitude, let longitude):
            return (latitude, longitude)
        }
    }

    @MainActor private func showTimeZoneCity() async {
        if let city = try? await Survey.timeZoneCity() { backdrop = (city.latitude, city.longitude) }
    }

    @MainActor private func keep(_ made: Edition, reworded: Bool = false) {
        edition = made
        LampStore.save(made, to: "edition")
        status = .ready
        onDelivery?(made)
        guard !reworded else { return }
        var recent = LampStore.load([String].self, from: "recentAnswers") ?? []
        recent = Array((made.puzzle.entries.map(\.answer) + recent).prefix(40))
        LampStore.save(recent, to: "recentAnswers")
    }

    /// Leaves out answers from the last few days while enough are left to make a good puzzle.
    private func fresh(_ candidates: [Candidate]) -> [Candidate] {
        let recent = Set(LampStore.load([String].self, from: "recentAnswers") ?? [])
        let today = Set(edition?.day == .today ? edition!.puzzle.entries.map(\.answer) : [])
        let unused = candidates.filter { !recent.contains($0.answer) || today.contains($0.answer) }
        let known = unused.filter { $0.tier == 0 }.count
        // The town and the main streets come round again: a puzzle without anything everyone knows isn't fair.
        if unused.count >= 18 && known >= 3 { return unused }
        return candidates.filter { $0.tier == 0 } + unused.filter { $0.tier > 0 }
    }

    /// The same day and place always make the same puzzle.
    private func seed(for place: Neighborhood) -> UInt64 {
        let spot = UInt64(bitPattern: Int64((place.latitude * 1_000).rounded())) &* 31 &+ UInt64(bitPattern: Int64((place.longitude * 1_000).rounded()))
        return UInt64(Day.today.number) &* 1_000_003 &+ spot
    }

    /// The AI's pass over the place, in the background. Today's clues are reworded only while nobody has
    /// started, since a clue changing under someone halfway through is worse than a plain one.
    @MainActor private func polish(_ place: Neighborhood, _ candidates: [Candidate]) async {
        guard let picks = await Polish.curate(candidates, in: place) else { return }
        // Only for the place it was asked about: the person may have moved on while the AI was answering, and
        // its clues were checked against this place's facts alone.
        guard let kept = LampStore.load(Neighborhood.self, from: "neighborhood"),
              kept.latitude == place.latitude, kept.longitude == place.longitude,
              abs(kept.gathered.timeIntervalSince(place.gathered)) < 1 else { return }
        var place = place
        place.curated = picks
        LampStore.save(place, to: "neighborhood")
        guard var today = edition, today.day == .today, today.latitude == place.latitude, today.longitude == place.longitude,
              canReword?() == true else { return }
        let clues = Dictionary(picks.map { ($0.answer, $0.clue) }, uniquingKeysWith: { a, _ in a })
        for index in today.puzzle.entries.indices {
            if let clue = clues[today.puzzle.entries[index].answer] { today.puzzle.entries[index].clue = clue }
        }
        keep(today, reworded: true)
    }

    /// Asked before rewording today's clues: true while no letter is in.
    var canReword: (() -> Bool)?
}
