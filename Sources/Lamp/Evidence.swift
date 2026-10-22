import Foundation

/// What a look actually established, said in a few lines at the end of its answer. The agent is told most of this in
/// pieces (a build line, a crash if there was one, a log tail, a picture) and was left to work out the rest, so its
/// ending claimed more than anyone saw: "it works" after a look at one screen. The note is built only from what Lamp
/// already knows of the look, for every kind of app, and says plainly what it doesn't know, so the ending
/// (`Agent.Rules.finish`) can claim just that. Where the app runs beyond the look is the device line's (`DeviceNote`).
enum Evidence {
    enum Launch: Equatable {
        /// Lamp opened it in this look and its first seconds passed with it open.
        case stayedOpen
        /// Lamp opened it in this look and pictured it before its first seconds were over.
        case stillStarting
        /// It died in its first seconds after Lamp opened it.
        case quit
        /// Lamp opened it, where nothing watches whether it stays open (the TV preview, a device app).
        case openedUnwatched
        /// It was open already and wasn't opened again.
        case alreadyOpen
    }

    enum Log: Equatable {
        case off
        case empty
        case lines(Int)
    }

    struct Facts {
        /// Where the look was: "this Mac", "the iPhone 17 simulator", "the TV preview on this Mac".
        var target: String
        var rebuilt: Bool
        var launch: Launch
        var log: Log
        /// How long before this answer its picture was taken; nil when there's none.
        var pictureAge: TimeInterval?
        var picturesOff: Bool
        /// The use_app calls in this request so far.
        var uses: Int
    }

    static func note(_ facts: Facts) -> String {
        let seconds = Int(Runtime.launchWindow.components.seconds)
        var lines = ["What Lamp observed in this look, which is all your ending may claim:"]
        lines.append("- Where: \(facts.target).")
        lines.append("- Build: " + (facts.rebuilt ? "built with your latest code." : "nothing needed building."))
        lines.append("- Launch: " + {
            switch facts.launch {
            case .stayedOpen: "Lamp opened it and it stayed open through its first \(seconds) seconds."
            case .stillStarting: "Lamp opened it and looked within its first \(seconds) seconds; a quit after that comes with your next look."
            case .quit: "Lamp opened it and it quit in its first \(seconds) seconds."
            case .openedUnwatched: "Lamp opened it; nothing there tells Lamp whether it stays open."
            case .alreadyOpen: "it was already open and wasn't opened again."
            }
        }())
        lines.append("- Log: " + {
            switch facts.log {
            case .off: "not shared with you (the person's privacy setting)."
            case .empty: "nothing printed since it was last opened."
            case .lines(let count): "\(count) \(count == 1 ? "line" : "lines") since it was last opened; the end of it is above."
            }
        }())
        lines.append("- Picture: " + (facts.picturesOff ? "not shared with you (the person's privacy setting)."
            : facts.pictureAge.map { "taken \(max(0, Int($0.rounded()))) seconds before this answer." } ?? "none."))
        lines.append("- Tests: Lamp ran none.")
        lines.append("- Tried: " + (facts.uses == 0
            ? "nothing was clicked, typed or pressed in the app in this request."
            : "use_app was called \(facts.uses) \(facts.uses == 1 ? "time" : "times") in this request; only what its answers showed was tried."))
        lines.append("- Unknown: anything the picture and log don't show, and what nobody tried.")
        return lines.joined(separator: "\n")
    }
}
