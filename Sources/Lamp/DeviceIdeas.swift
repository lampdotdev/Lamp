import Foundation

/// Wishes for the devices Lamp found on the person's network, made up by the model from all of them at once: what's
/// possible with a TV, a console, a phone, speakers and lights together is the model's to see, not a list of Lamp's.
/// Asked when the person opens Your Devices (`DeskDevices`), once for each set of devices, and again when they ask for
/// others. The model is told only what each device is (maker, model, software, what Lamp can do with it), numbered:
/// never the names people give their devices, which are often their own or their home's, nor what a device said of
/// itself on the network, which can carry serial numbers and hardware addresses. The names go back on here.
@MainActor final class DeviceIdeas: ObservableObject {
    static let shared = DeviceIdeas()

    struct Idea: Identifiable, Equatable {
        /// The wish, in the person's words, as it goes in the bar.
        let wish: String
        /// The devices it uses, by their names on this Mac.
        let devices: [String]
        var id: String { wish }
    }

    @Published private(set) var ideas: [Idea] = []
    @Published private(set) var thinking = false
    /// The devices the ideas are for, so a look that finds the same ones keeps them.
    private var madeFor: String?
    private var asked = 0

    /// Ideas for these devices: kept when they're the same ones, made up afresh when they changed or `again`.
    func think(about devices: [Device], again: Bool = false) {
        let key = devices.map(\.id).sorted().joined(separator: "\n")
        guard !devices.isEmpty else { ideas = []; madeFor = nil; return }
        guard again || key != madeFor else { return }
        asked += 1
        let ask = asked, avoiding = again ? ideas.map(\.wish) : []
        thinking = true
        Task {
            let made = await Self.invent(for: devices, avoiding: avoiding)
            guard ask == asked else { return }
            thinking = false
            if let made {
                ideas = made
                madeFor = key
            }
        }
    }

    private static let prompt = """
    You suggest wishes to someone who uses Lamp, a Mac app that makes software from a wish typed in plain words, \
    built for them by an AI agent. Lamp makes Mac apps (windows, the menu bar, widgets), iPhone, iPad and Apple \
    Watch apps, Android apps, apps for Samsung and LG TVs, Xbox games and apps, Roku channels, games played on any \
    of those, and full-screen pages for a TV or an iPad. One wish can be several apps made to work together: they \
    find each other on the home network and send each other messages, shared values and files, even with Lamp \
    closed. An app can also talk to any other device on the network through whatever that device offers (its own \
    local API, its web page, the protocols it answers), and to services the person uses.

    These are the devices Lamp found on their network just now, numbered, with what Lamp knows of each:
    {{DEVICES}}

    Suggest six wishes they could type, made for these devices. Surprise them: the best use two or more of the \
    devices together, or use one in a way its maker never offered, and each is something they'd use again and \
    again or show a friend. Only what these devices can really do. Write each as they would ask for it, in one \
    sentence of at most 20 words, naming the devices the way they would ("my TV", "the Xbox", "the speaker"), never \
    an app's name, and no two alike.{{AVOID}}

    Respond with JSON: {"ideas": [{"wish": "...", "devices": [the numbers of the devices it uses]}]}
    """

    /// One line for each device, numbered from 1: what it is and what Lamp can do with it, never its name.
    static func described(_ devices: [Device]) -> String {
        devices.prefix(24).enumerated().map { index, device in
            // "Roku Express" rather than "Roku Roku Express": a model often starts with its maker's name.
            let maker = device.model.lowercased().hasPrefix(device.maker.lowercased()) ? "" : device.maker
            let what = [maker, device.model].filter { !$0.isEmpty }.joined(separator: " ")
            let software = [device.os, device.osVersion].filter { !$0.isEmpty }.joined(separator: " ")
            var line = "\(index + 1). " + (what.isEmpty ? device.kind.name : what) + (software.isEmpty ? "" : ", \(software)")
            switch device.kind {
            case .iphone, .ipad, .android, .samsungTV, .lgTV: line += ": Lamp puts apps on it"
            case .other:
                if let id = device.integration, DeviceApps.makesApps(id) { line += ": Lamp puts apps on it" }
                else if device.integration != nil { line += ": Lamp knows how to reach it" }
                else { line += ": Lamp doesn't know it yet" }
            default: break
            }
            return line
        }.joined(separator: "\n")
    }

    private static func invent(for devices: [Device], avoiding: [String]) async -> [Idea]? {
        let shown = Array(devices.prefix(24))
        let request = prompt.replacingOccurrences(of: "{{DEVICES}}", with: described(devices))
            .replacingOccurrences(of: "{{AVOID}}", with: avoiding.isEmpty ? "" : "\n\nNot these, which they've seen:\n" + avoiding.map { "- " + $0 }.joined(separator: "\n"))
        guard let (text, _) = try? await AppAI.complete(prompt: request, images: [], system: "", json: true,
                                                         model: await AppAI.helperModel()),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let list = object["ideas"] as? [[String: Any]] else { return nil }
        let ideas = list.compactMap { entry -> Idea? in
            guard let wish = (entry["wish"] as? String)?.trimmed, !wish.isEmpty, wish.count <= 200 else { return nil }
            let numbers = (entry["devices"] as? [Any] ?? []).compactMap { ($0 as? Int) ?? ($0 as? String).flatMap { Int($0) } }
            return Idea(wish: wish, devices: numbers.filter { (1...shown.count).contains($0) }.map { shown[$0 - 1].name })
        }
        return ideas.isEmpty ? nil : Array(ideas.prefix(6))
    }
}
