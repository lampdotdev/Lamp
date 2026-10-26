import Foundation

/// The apps a wish has taken away (`remove_app`, or a version restored without them), each as Lamp knew it: they left
/// reversibly, keeping what they saved, here and on the person's devices, so Undo or a restore brings them back as they
/// were. Deleting the wish disposes of each for good, with its present apps, so nothing an app left behind outlives it.
/// Kept in the wish's `.lamp/removed-apps.json`, Lamp's own, one record per identity an app left as (`Identity`), never
/// dropped: an app made again in the same folder may be something else (a game that was on an Xbox, now on the Mac
/// alone), and what the one before left on the devices is still to be taken off.
struct RemovedApp: Codable, Equatable {
    var id: String
    var name: String
    var exe: String
    /// Its folder in the wish's, or nil for the app that was in the wish's own folder.
    var folder: String?
    var instance: String
    var platform: Platform
    var family: DeviceFamily
    var places: [Destination]?
    var integration: String?
    var device: String?

    init(_ app: LampProject) {
        id = app.id
        name = app.name
        exe = app.exe
        folder = app.isPart ? app.dir.lastPathComponent : nil
        instance = app.instance
        platform = app.platform
        family = app.family
        places = app.places
        integration = app.integration
        device = app.device
    }

    /// The app as Lamp's disposal reads it, in its wish's folder (`wish`).
    func project(in wish: LampProject) -> LampProject {
        LampProject(id: id, name: name, exe: exe, dir: folder.map { wish.dir.appendingPathComponent($0) } ?? wish.dir,
                    instance: instance, platform: platform, integration: integration, family: family, device: device,
                    places: places, partOf: folder == nil ? nil : wish.id)
    }

    /// What disposing of an app goes by: everything Lamp keeps of it but its names.
    struct Identity: Hashable {
        let id: String, folder: String?, instance: String, platform: Platform, family: DeviceFamily
        let places: [Destination]?, integration: String?, device: String?
    }

    var identity: Identity {
        Identity(id: id, folder: folder, instance: instance, platform: platform, family: family, places: places,
                 integration: integration, device: device)
    }

    /// The apps deleting the wish disposes of beside the one in its own folder, which goes with the wish itself: its other
    /// present apps (`parts`), then each identity its apps taken away left as that no present app is, once each.
    static func disposals(of wish: LampProject, parts: [LampProject]) -> [LampProject] {
        var seen = Set((parts + (wish.holdsApp ? [wish] : [])).map { RemovedApp($0).identity })
        return parts + list(in: wish.dir).filter { seen.insert($0.identity).inserted }.map { $0.project(in: wish) }
    }

    static func file(of wish: URL) -> URL { wish.appendingPathComponent(".lamp/removed-apps.json") }

    static func list(in wish: URL) -> [RemovedApp] {
        guard let data = AppFile.read(file(of: wish), inFolder: wish) else { return [] }
        return (try? JSONDecoder().decode([RemovedApp].self, from: data)) ?? []
    }

    /// Keeps the record of an app of the wish in `wish` that's just been taken away, beside those before it: one per
    /// identity, the latest names kept.
    static func record(_ app: LampProject, in wish: URL) {
        let removed = RemovedApp(app)
        let kept = list(in: wish).filter { $0.identity != removed.identity } + [removed]
        guard let data = try? JSONEncoder().encode(kept) else { return }
        try? AppFolder.write(String(decoding: data, as: UTF8.self), to: file(of: wish), in: wish)
    }
}
