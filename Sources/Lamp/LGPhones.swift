import Foundation
import LampRelayKit

/// A game's phones on an LG TV, run by the game itself: Lamp packages a JS service of LG's kind with the game
/// (`Resources/LGPhones`: `service.js` on the TV's service bus, `relay.js` serving the phone page and the relay its
/// phones and its page meet at, with ws for WebSocket framing), and the game's page starts it through a subscription
/// when it chooses it, `Lamp.controllers.start({ host: 'game' })` (lamp.js, named at `TVTemplate.lgServiceMarker` in
/// that package's copy only). On that host the page doesn't ask Lamp, so phones play on with the Mac asleep, closed or
/// gone; `start({ host: 'lamp' })` in the same package has Lamp host them instead. The service carries the phone page Lamp
/// published at the build, checked as a Mac game's is (`ControllerSnapshot`), with Lamp's lamp-controller.js, so a new
/// build never changes the page under a game that's being played.
///
/// It goes only where it can run, a fact of the package decided as it's made: a game that takes phones and has
/// a phone page, an app id LG takes as the start of a service's name, and a TV whose webOS is 5 or later (webOS TV 5.0,
/// whose Node, 8.12, is the oldest ws runs on). Elsewhere (an older TV, or one whose version Lamp hasn't read) the
/// package has no service, and a page that chooses the game's own host hears it isn't there.
enum LGPhones {
    static let oldestRelease = 5

    /// Lamp's copy of the service, in its bundle.
    static var source: URL? { Bundle.main.resourceURL?.appendingPathComponent("LGPhones") }

    /// The service's name: the game's app id with ".phones", as LG's naming asks (it starts with the app's id), when the
    /// app's id is one a service's name may start with.
    static func serviceID(for project: LampProject) -> String? {
        let id = TVTemplate.webOSID(for: project) + ".phones"
        return isServiceName(id) ? id : nil
    }

    /// LG's rule for a service's name: no minus sign, and no period followed by a digit; letters, digits and dots here.
    static func isServiceName(_ id: String) -> Bool {
        let steps = id.split(separator: ".", omittingEmptySubsequences: false)
        return id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }
            && steps.count > 1 && steps.allSatisfy { !$0.isEmpty && !$0.first!.isNumber }
    }

    /// Whether a TV's webOS runs the service: its release (`TVs.Record.osVersion`, the TV's `webos_release`) is 5 or later.
    static func runs(on osVersion: String) -> Bool {
        Int(osVersion.split(separator: ".").first ?? "").map { $0 >= oldestRelease } ?? false
    }

    struct Service {
        let id: String
        /// Paths inside the service's folder, and their bytes.
        let files: [(path: String, data: Data)]
    }

    /// The service for this game on this TV, nil when its phones stay Lamp's there.
    /// `guarded`: a shared game's network policy (`TVNetworkGuard`), put in each page of its phone page, which phones
    /// open from the TV at its address.
    static func service(for project: LampProject, on record: TVs.Record, source: URL? = source, guarded: TVNetworkGuard.Policy? = nil) throws -> Service? {
        guard project.platform.target.takesPhones, runs(on: record.osVersion), TVs.hasPhonePage(project),
              let id = serviceID(for: project) else { return nil }
        guard let source else { throw TVs.Failure(message: "Lamp's phone service for LG TVs is missing from Lamp.") }
        let published = try ControllerSnapshot.read(TVs.phoneFolder(for: project))
        var mine = published.files.filter { $0.path != "lamp-controller.js" }
        if let guarded {
            let policy = TVNetworkGuard.phonePage(guarded, relayHost: record.address)
            mine = mine.map { TVNetworkGuard.isPage($0.path) ? ControllerSnapshot.File(path: $0.path, data: TVNetworkGuard.guarded($0.data, policy: policy)) : $0 }
        }
        let page = ControllerSnapshot(files: mine + [ControllerSnapshot.File(path: "lamp-controller.js", data: Data(TVTemplate.phoneControllerJS.utf8))])
        do { try page.check() } catch { throw TVs.Failure(message: "\(error)") }
        return Service(id: id, files: try files(id: id, owner: TVTemplate.webOSID(for: project), page: page, source: source))
    }

    /// The service's own files (from Lamp's copy, links refused), what describes it to the TV, and the phone page.
    static func files(id: String, owner: String, page: ControllerSnapshot, source: URL) throws -> [(path: String, data: Data)] {
        var files: [(path: String, data: Data)] = []
        let base = source.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        let walk = FileManager.default.enumerator(at: source, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])?.allObjects ?? []
        for case let url as URL in walk {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { throw TVs.Failure(message: "Lamp's phone service for LG TVs has a link in it.") }
            guard values.isRegularFile == true else { continue }
            files.append((String(url.standardizedFileURL.path.dropFirst(base.count + 1)), try Data(contentsOf: url)))
        }
        guard files.contains(where: { $0.path == "service.js" }), files.contains(where: { $0.path == "relay.js" }) else {
            throw TVs.Failure(message: "Lamp's phone service for LG TVs is missing from Lamp.")
        }
        let package: [String: Any] = ["name": id, "version": "1.0.0", "main": "service.js",
                                      "lamp": ["service": id, "owner": owner, "app": owner]]
        let services: [String: Any] = ["id": id, "description": "Phones as controllers for this game",
                                       "services": [["name": id, "description": "Phones as controllers for this game"]]]
        files.append(("package.json", try JSONSerialization.data(withJSONObject: package, options: [.prettyPrinted, .sortedKeys])))
        files.append(("services.json", try JSONSerialization.data(withJSONObject: services, options: [.prettyPrinted, .sortedKeys])))
        files += page.files.map { ("phone/" + $0.path, $0.data) }
        return files.sorted { $0.path < $1.path }
    }

    /// Whether a game's lamp.js has the place to name its service: one written by a Lamp from before it doesn't.
    static func names(_ lampJS: Data) -> Bool { String(decoding: lampJS, as: UTF8.self).contains(TVTemplate.lgServiceMarker) }

    /// The game's lamp.js naming its service, which `start({ host: 'game' })` uses.
    static func naming(_ lampJS: Data, service id: String) throws -> Data {
        let text = String(decoding: lampJS, as: UTF8.self)
        guard text.contains(TVTemplate.lgServiceMarker),
              let quoted = try? JSONSerialization.data(withJSONObject: [id]) else {
            throw TVs.Failure(message: "The game's lamp.js has no place to name its phone service.")
        }
        let value = String(decoding: quoted, as: UTF8.self).dropFirst().dropLast()
        return Data(text.replacingOccurrences(of: TVTemplate.lgServiceMarker, with: "/*LAMP_LG_SERVICE*/" + value).utf8)
    }
}
