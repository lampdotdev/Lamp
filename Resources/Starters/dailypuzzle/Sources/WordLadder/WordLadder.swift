import Foundation

/// One day's ladder: climb from `start` to `end` one letter at a time. `par` is the fewest steps it can be done in.
struct LadderPuzzle: Equatable {
    let start: String
    let end: String
    let par: Int
}

/// The rules of Word Ladder and the day's puzzle. Everything here is plain functions over `Words.all`, so the
/// game model and the samples ask the same questions and get the same answers.
enum WordLadder {
    static let length = 4

    /// Start and end words whose shortest ladder through `Words.all` is four to six steps: long enough to need a
    /// plan, short enough for a coffee. The order is the order the days take them in, mixed so two days running
    /// don't feel alike; a new pair can go anywhere, but check its par stays in that range.
    static let pairs: [(String, String)] = [
        ("hand", "palm"), ("pear", "plum"), ("core", "root"), ("lake", "pond"), ("mind", "body"), ("tent", "camp"),
        ("sand", "dune"), ("lily", "pond"), ("mist", "rain"), ("duck", "pond"), ("dawn", "noon"), ("lark", "song"),
        ("long", "tall"), ("sour", "milk"), ("sink", "swim"), ("send", "mail"), ("hope", "fear"), ("head", "tail"),
        ("push", "pull"), ("dusk", "dawn"), ("goat", "milk"), ("hard", "easy"), ("heel", "toes"), ("poem", "word"),
        ("hand", "foot"), ("kite", "wind"), ("love", "hate"), ("silk", "wool"), ("meal", "dine"), ("boat", "sail"),
        ("lime", "pear"), ("read", "book"), ("hide", "seek"), ("deer", "park"), ("noon", "dusk"), ("crab", "claw"),
        ("mice", "cats"), ("pear", "tart"), ("rock", "sand"), ("worm", "bird"), ("fork", "dish"), ("tame", "wild"),
        ("bean", "corn"), ("shoe", "sock"), ("bake", "cook"), ("talk", "chat"), ("nest", "bird"), ("ship", "port"),
        ("wake", "rest"), ("wind", "calm"), ("kite", "sail"), ("fish", "bird"), ("corn", "rice"), ("book", "page"),
        ("ruin", "mend"), ("snow", "melt"), ("wave", "surf"), ("hike", "camp"), ("gold", "mine"), ("seed", "corn"),
        ("coal", "fire"), ("bake", "loaf"), ("heat", "wave"), ("ride", "walk"), ("pigs", "farm"), ("star", "glow"),
        ("wood", "fire"), ("nose", "face"), ("sock", "boot"), ("ring", "bell"), ("milk", "cake"), ("moon", "tide"),
        ("cook", "fire"), ("moth", "lamp"), ("cake", "wish"), ("rain", "pour"), ("team", "goal"), ("give", "take"),
        ("soup", "meal"), ("song", "note"), ("golf", "ball"), ("mild", "warm"), ("bowl", "soup"), ("desk", "work"),
        ("team", "play"), ("coat", "hood"), ("face", "mask"), ("cold", "heat"), ("fast", "slow"), ("ship", "dock"),
        ("more", "less"), ("cold", "warm"), ("seed", "tree"), ("card", "gift"), ("lead", "gold"), ("lose", "find"),
        ("bees", "hive"), ("word", "game"), ("moon", "star"), ("lift", "load"), ("last", "time"), ("rose", "pink"),
        ("cool", "heat"),
    ]

    /// The puzzle for a day. It depends on the date alone, so it stays the same all day, changes at midnight and
    /// is the same on every Mac.
    static func puzzle(for day: Day) -> LadderPuzzle {
        let index = ((day.number % pairs.count) + pairs.count) % pairs.count
        let (start, end) = pairs[index]
        let par = shortestPath(from: start, to: end).map { $0.count - 1 } ?? 0
        return LadderPuzzle(start: start, end: end, par: par)
    }

    static func isWord(_ word: String) -> Bool {
        Words.all.contains(word)
    }

    /// The positions where two words of the same length differ.
    static func differences(_ a: String, _ b: String) -> [Int] {
        zip(Array(a), Array(b)).enumerated().compactMap { $0.element.0 == $0.element.1 ? nil : $0.offset }
    }

    /// Every word one letter away from `word`.
    static func neighbors(of word: String) -> [String] {
        let letters = Array(word)
        var found: [String] = []
        for position in letters.indices {
            for letter in "abcdefghijklmnopqrstuvwxyz" where letter != letters[position] {
                var changed = letters
                changed[position] = letter
                let candidate = String(changed)
                if Words.all.contains(candidate) { found.append(candidate) }
            }
        }
        return found
    }

    /// The shortest ladder from one word to another, both ends included, or nil when there's none. A plain
    /// breadth-first search: with a couple of thousand words it takes a few milliseconds.
    static func shortestPath(from start: String, to end: String) -> [String]? {
        guard start != end else { return [start] }
        var previous: [String: String] = [start: start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let word = queue[head]
            head += 1
            for next in neighbors(of: word) where previous[next] == nil {
                previous[next] = word
                if next == end {
                    var path = [end]
                    while let step = previous[path[0]], step != path[0] { path.insert(step, at: 0) }
                    return path
                }
                queue.append(next)
            }
        }
        return nil
    }
}
