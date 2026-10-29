import Foundation
import LampRelayKit

/// A game's phone page in its Mac copy and its Xbox package: the game serves it, and runs the relay its phones join, itself
/// (`ControllerRuntime`, built into every game from `GameKit.controllerKit`), so its phones never need Lamp. Lamp's
/// part is only to put the page in the bundle as it installs the game: the copy of Phone/ it published at the build
/// (`TVs.stagePhone`, which turns away links), checked again as it's read, with Lamp's lamp-controller.js beside it.
/// The page is in the bundle, so it's signed with the game, and a change to it goes in as the game is installed again.
enum GamePhones {
    /// Where the page goes in a Mac app's bundle, which LampPage.swift serves from.
    static let folder = "Contents/Resources/Phone"

    static func takes(_ project: LampProject) -> Bool {
        project.platform.target.takesPhones && project.hasMac
    }

    /// The page as the game is to serve it, nil when the game has none.
    static func page(for project: LampProject) throws -> ControllerSnapshot? {
        guard takes(project), TVs.hasPhonePage(project) else { return nil }
        return try snapshot(of: project)
    }

    /// The page as the game's Xbox package carries it (`Phone/` beside the host, `WebHost.payload`), which the host there
    /// serves itself with the game's own relay (lamp_controllers.h): nil when the game has none.
    static func xboxPage(for project: LampProject) throws -> ControllerSnapshot? {
        guard project.platform.target.takesPhones, TVs.hasPhonePage(project) else { return nil }
        return try snapshot(of: project)
    }

    /// The published page with Lamp's lamp-controller.js, checked.
    private static func snapshot(of project: LampProject) throws -> ControllerSnapshot {
        let published = try ControllerSnapshot.read(TVs.phoneFolder(for: project))
        let page = ControllerSnapshot(files: published.files.filter { $0.path != "lamp-controller.js" }
            + [ControllerSnapshot.File(path: "lamp-controller.js", data: Data(TVTemplate.phoneControllerJS.utf8))])
        try page.check()
        return page
    }

    /// Puts the page in the copy being installed, in place of any it had; a game without one has none.
    static func bundle(_ project: LampProject, into app: URL) throws {
        let target = app.appendingPathComponent(folder)
        try? FileManager.default.removeItem(at: target)
        guard let page = try page(for: project) else { return }
        try page.write(to: target)
    }

    /// Whether the page published now differs from the one in the game's installed copy: a change that can't go into the
    /// open game as it's played, since the game serves the page from its bundle.
    static func changed(_ project: LampProject) -> Bool {
        guard takes(project) else { return false }
        let installed = try? ControllerSnapshot.read(project.installedURL.appendingPathComponent(folder))
        let published = try? page(for: project)
        return (installed.flatMap { $0.files.isEmpty ? nil : $0.digest }) != published?.digest
    }
}
