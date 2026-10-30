import Foundation
import LampRelayKit

/// The sites an app's phone page may reach beyond its own files and its game's relay (`PhonePagePolicy`), for every
/// server of one: Lamp's (`Store.phonePage`), and the copy Lamp puts in a game's bundle, an LG TV's service or an Xbox
/// package (`snapshot`). An app shared with the person is held to the sites its safety review named, the same policy its
/// other pages are held to (`SharedNetwork`); one the person made, or let reach every site, reaches any https site.
enum PhonePageReach {
    static func reach(_ project: LampProject) -> PhonePagePolicy.Reach {
        reach(SharedNetwork.policy(for: project))
    }

    /// Sites the person allowed on a device are that device's (the app's own defaults), so a phone page, served from
    /// elsewhere, has only the review's.
    static func reach(_ policy: NetworkPolicy?) -> PhonePagePolicy.Reach {
        guard let policy, policy.restricts else { return .secureSites }
        return .only(policy.origins)
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
