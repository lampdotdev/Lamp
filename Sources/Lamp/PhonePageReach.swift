import Foundation
import LampRelayKit

/// The sites an app's phone page may reach beyond its own files and its game's relay (`PhonePagePolicy`), for every
/// server of one: Lamp's (`Store.phonePage`), and the copy Lamp puts in a game's bundle, an LG TV's service or an Xbox
/// package (`snapshot`). Which sites an app shared with the person may reach is the shared-app policy's to say, the same
/// one its other pages are held to; this reads it in one place, so the phone pages follow whatever it decides.
enum PhonePageReach {
    /// The shared-app policy's answer for an app: nil for one the person made here, else the sites a shared app's pages
    /// may reach. Until that policy is wired in, every app is taken as the person's own.
    nonisolated(unsafe) static var sharedSites: (LampProject) -> [String]? = { _ in nil }

    static func reach(_ project: LampProject) -> PhonePagePolicy.Reach {
        sharedSites(project).map { .only($0) } ?? .secureSites
    }

    /// A page's files as a game's bundle, an LG TV or an Xbox package carries it: Lamp's lamp-controller.js and the reach
    /// file in place of any of the app's own by those names.
    static func snapshot(_ published: ControllerSnapshot, of project: LampProject, controller: Data) -> ControllerSnapshot {
        let lamps: Set<String> = ["lamp-controller.js", PhonePagePolicy.reachFile]
        return ControllerSnapshot(files: published.files.filter { !lamps.contains($0.path) }
            + [ControllerSnapshot.File(path: "lamp-controller.js", data: controller),
               ControllerSnapshot.File(path: PhonePagePolicy.reachFile, data: PhonePagePolicy.json(reach(project)))])
    }
}
