import Foundation

/// What a game's page is told about the device it's on, so it never works out where it is: the device's row in the
/// table of devices is resolved once for the copy of the page being made (`place`), and its input (`Place.Input`) is
/// written beside lamp-game.js in that copy as `lamp-device.js` (`stage`). Every copy goes through here: the
/// preview's, a build for the Mac, the simulator or Android (build.sh writes what `buildEnvironment` hands it), a real
/// iPhone's or iPad's (`Devices.stage`), the copy of the app an integration's package step runs on (`DeviceApps`) and a
/// published page (`Publish`). The app's own Web/ never holds one, so a copy made some other way fails to load rather
/// than claiming another device's facts.
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
    /// destination given (the preview is played on this Mac). The project's family picks out its row among those
    /// sharing a destination (an iOS app built for an Apple TV is the Apple TV's), and that row must show a page;
    /// an integration's device is its own row.
    static func place(for project: LampProject, at destination: Destination? = nil) throws -> Place {
        let destination = destination ?? project.destination
        if destination == .device {
            guard let id = project.deviceIntegration, let row = Places.all.first(where: { $0.id == id }) else {
                throw Failure(message: "Lamp doesn't know the device \(project.deviceIntegration ?? "this game") is for.")
            }
            return row
        }
        let here = Places.builtIn.filter { $0.destination == destination && ($0.families.isEmpty || $0.families.contains(project.family)) }
        let pages = here.filter { $0.runs(.web) }
        guard pages.count == 1, let row = pages.first else {
            let named = here.first { $0.families.contains(project.family) } ?? here.first
            throw Failure(message: "\(named?.name ?? "That device") can't show a game's page" + (named?.noWeb.map { " (\($0))" } ?? "") + ".")
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

    /// A page published to the web is played in whatever browser opens it, on no one device: it names a key both ways
    /// where keyboards differ (`Place.Input.anyKeyboard`), and has no controller of its own.
    static let anyBrowser = (id: "any-browser", name: "a browser on any device", input: Place.Input.anyKeyboard)

    static func descriptor(id: String, name: String, input: Place.Input) throws -> String {
        if let problem = Controllers.problem(in: input) { throw Failure(message: "\(name): \(problem)") }
        var facts: [String: Any] = ["keys": input.keys ?? [:]]
        if let controller = input.controller { facts["controller"] = controller }
        if let layout = input.layout { facts["layout"] = layout }
        return "// Written by Lamp for the device this copy of the game is on (\(id)); don't edit.\nexport default \(json(facts));\n"
    }

    /// Writes the device beside the runtime in a copy of the page; nothing in a page that isn't a game's. The copy is
    /// made from the app's files, so it's read and written within `root` (`AppFile`, `AppFolder`), no link followed:
    /// a link the copy kept can't carry the write anywhere else.
    static func stage(_ page: URL, in root: URL, for place: Place) throws {
        try stage(page, in: root, descriptor: { try descriptor(for: place) })
    }

    static func stage(_ page: URL, in root: URL, descriptor: () throws -> String) throws {
        guard AppFile.read(page.appendingPathComponent(runtimeFile), inFolder: root) != nil else { return }
        try AppFolder.write(try descriptor(), to: page.appendingPathComponent(deviceFile), in: root)
    }

    /// What build.sh is handed to write into the copy of the page it builds (`LAMP_PAGE_DEVICE`): the device the
    /// project is built for now. Only a web game on Lamp's game runtime gets this device descriptor.
    static func buildEnvironment(for project: LampProject) throws -> [String: String] {
        guard GameKit.isGame(project), GameKit.engine(project) == .web else { return [:] }
        return ["LAMP_PAGE_DEVICE": try descriptor(for: place(for: project))]
    }

    /// Whether every copy of the runtime in a staged page or app has this device beside it, as `stage` wrote it: read
    /// in the copy the package step ran on.
    static func check(_ folder: URL, for place: Place) throws {
        let expected = Data(try descriptor(for: place).utf8)
        let found = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for runtime in found where runtime.lastPathComponent == runtimeFile {
            let beside = runtime.deletingLastPathComponent().appendingPathComponent(deviceFile)
            guard AppFile.read(beside, inFolder: folder) == expected else {
                throw Failure(message: "\(runtime.path.dropFirst(folder.path.count + 1)) has no \(deviceFile) for \(place.name) beside it.")
            }
        }
    }

    /// The same in a package's files, where Lamp knows how to read the package (a ZIP, and so an MSIX made from one):
    /// what the device gets is what the package step took, which the copy alone doesn't prove.
    static func check(payload files: [(path: String, data: Data)], for place: Place) throws {
        let expected = Data(try descriptor(for: place).utf8)
        let byPath = Dictionary(files.map { ($0.path, $0.data) }, uniquingKeysWith: { a, _ in a })
        for file in files where (file.path as NSString).lastPathComponent == runtimeFile {
            let beside = ((file.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(deviceFile)
            guard byPath[beside] == expected else {
                throw Failure(message: "The package's \(file.path) has no \(deviceFile) for \(place.name) beside it: the package step must take the page's whole folder.")
            }
        }
    }

    /// What the copy of the project's page is told where it's built for now, as part of what its build is made from
    /// (`GameTarget`'s inputs): a change to that device's row builds the game again. What stops it being resolved is
    /// said instead, so the build that follows says it too.
    static func buildInput(for project: LampProject) -> String {
        do { return try descriptor(for: place(for: project)) } catch { return error.localizedDescription }
    }

    /// JSON as the page reads it: keys sorted, so a copy changes only when what it says does.
    static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
