import Foundation

/// What a game's page is told about the device it's on, so it never works out where it is: the device's row in the
/// table of devices is resolved once for the copy of the page being made (`place`), and its input (`Place.Input`) is
/// written beside lamp-game.js in that copy as `lamp-device.js` (`stage`). Every copy goes through here: the
/// preview's, a build for the Mac, the simulator or Android (build.sh writes what `buildEnvironment` hands it), a real
/// iPhone's or iPad's (`Devices.stage`) and an integration's package (`DeviceApps`). The app's own Web/ never holds
/// one, so a copy made some other way fails to load rather than claiming another device's facts.
enum GamePage {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The file lamp-game.js imports the device from, beside it in every copy of the page.
    static let deviceFile = "lamp-device.js"
    /// The runtime whose presence makes a page a game's, which needs the device.
    static let runtimeFile = "lamp-game.js"

    /// The row of the device this copy of the project's page is for: where the project is built for now, or the
    /// destination given (the preview is played on this Mac). One row of the table that runs a page there, picked
    /// out by the project's family where several do; an integration's device is its own row.
    static func place(for project: LampProject, at destination: Destination? = nil) throws -> Place {
        let destination = destination ?? project.destination
        if destination == .device {
            guard let id = project.deviceIntegration, let row = Places.all.first(where: { $0.id == id }) else {
                throw Failure(message: "Lamp doesn't know the device \(project.deviceIntegration ?? "this game") is for.")
            }
            return row
        }
        var rows = Places.builtIn.filter { $0.destination == destination && $0.runs(.web) }
        if rows.count > 1 { rows = rows.filter { $0.families.contains(project.family) } }
        guard rows.count == 1, let row = rows.first else {
            throw Failure(message: "Lamp has no one device that shows a game's page there (\(destination)).")
        }
        return row
    }

    /// `lamp-device.js` for a copy of the page on this device: its row's input. A row that doesn't say what its keyboard
    /// and controller are has nothing to tell the page, so the copy isn't made.
    static func descriptor(for place: Place) throws -> String {
        guard let input = place.input else {
            throw Failure(message: "Lamp doesn't know what \(place.name)'s keys and controller are called, so it can't put a game there."
                + " Its integration says so in input.")
        }
        return try descriptor(id: place.id, name: place.name, input: input)
    }

    /// A page published to the web is played in whatever browser opens it, on no one device: it's told the generic
    /// input, said as such.
    static let anyBrowser = (id: "any-browser", name: "a browser on any device", input: Place.Input.generic)

    static func descriptor(id: String, name: String, input: Place.Input) throws -> String {
        if let problem = Controllers.problem(in: input) { throw Failure(message: "\(name): \(problem)") }
        var facts: [String: Any] = ["keys": input.keys ?? [:]]
        if let controller = input.controller { facts["controller"] = controller }
        if let layout = input.layout { facts["layout"] = layout }
        return "// Written by Lamp for the device this copy of the game is on (\(id)); don't edit.\nexport default \(json(facts));\n"
    }

    /// Writes the device beside the runtime in a copy of the page; nothing in a page that isn't a game's. A copy in
    /// Lamp's own folder is written as any file; the app's own page goes through `write` (`Template.put`).
    static func stage(_ page: URL, for place: Place, write: ((String, URL) throws -> Void)? = nil) throws {
        try stage(page, descriptor: { try descriptor(for: place) }, write: write)
    }

    static func stage(_ page: URL, descriptor: () throws -> String, write: ((String, URL) throws -> Void)? = nil) throws {
        guard FileManager.default.fileExists(atPath: page.appendingPathComponent(runtimeFile).path) else { return }
        let text = try descriptor(), url = page.appendingPathComponent(deviceFile)
        if let write { try write(text, url) } else { try Data(text.utf8).write(to: url, options: .atomic) }
    }

    /// What build.sh is handed to write into the copy of the page it builds (`LAMP_PAGE_DEVICE`): the device the
    /// project is built for now. Only a three.js game's page has the runtime.
    static func buildEnvironment(for project: LampProject) throws -> [String: String] {
        guard GameKit.isGame(project), GameKit.engine(project) == .web else { return [:] }
        return ["LAMP_PAGE_DEVICE": try descriptor(for: place(for: project))]
    }

    /// Whether every copy of the runtime in a package has this device beside it, as `stage` wrote it.
    static func check(_ files: [(path: String, data: Data)], for place: Place) throws {
        let expected = Data(try descriptor(for: place).utf8)
        let byPath = Dictionary(files.map { ($0.path, $0.data) }, uniquingKeysWith: { a, _ in a })
        for file in files where (file.path as NSString).lastPathComponent == runtimeFile {
            let beside = ((file.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(deviceFile)
            guard byPath[beside] == expected else {
                throw Failure(message: "The package's \(file.path) has no \(deviceFile) for \(place.name) beside it: its package step must take the whole page folder.")
            }
        }
    }

    /// JSON as the page reads it: keys sorted, so a copy changes only when what it says does.
    static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
