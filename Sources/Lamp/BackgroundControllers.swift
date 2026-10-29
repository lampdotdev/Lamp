import Foundation
import LampRelayKit
import Security
import ServiceManagement

/// Phones as controllers for a game on this Mac while Lamp is closed: the person turns it on in Settings, and Lamp
/// registers its controllers service (`ControllerService`, `LampControllerService` in Lamp's Helpers) with macOS as a
/// launch agent, which macOS starts at login and keeps running until they turn it off. Lamp then hands the service each
/// game it installs (its phone page, a key of the game's own, and the signature it's installed with), and writes into
/// the game's copy where the service is and which build of its page it has. The game asks the service for its session
/// itself (LampPage.swift), so its phones go on playing, and new ones join, after Lamp quits.
///
/// Only a Mac game with a phone page built while this is on goes through the service; any other app's page and game
/// (a TV app's, the TV preview's, a game built before) stays Lamp's own, which ends with Lamp (`PhoneControllers`).
/// Lamp never starts, stops or restarts the service itself: macOS does, and what the person turns off in System
/// Settings stays off.
enum BackgroundControllers {
    static let names = ControllerService.Names(bundleID: Edition.bundleID)

    private static var agent: SMAppService { SMAppService.agent(plistName: names.plistName) }

    enum State: Equatable {
        case off
        case on
        /// Registered, waiting for the person to allow it in System Settings → Login Items.
        case needsApproval
        /// This build has no service in it (a build without one, as `swift run` makes).
        case missing
    }

    /// What macOS says of the service, never what was last chosen here.
    static var state: State {
        switch agent.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        case .notFound: .missing
        default: .off
        }
    }

    /// Turns it on or off; returns what went wrong, in words, or nil. Turned off, macOS stops the service, and the
    /// games' phones are let go.
    @MainActor static func set(_ on: Bool) -> String? {
        do {
            if on { try agent.register() } else { try agent.unregister() }
        } catch {
            if on, agent.status == .requiresApproval { return nil }
            return on ? "macOS didn't let Lamp keep phone controllers working with Lamp closed: \(error.localizedDescription)"
                      : "macOS didn't stop the phone controllers service: \(error.localizedDescription)"
        }
        if !on { setHosted([]) }
        return nil
    }

    static func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    // MARK: The games it hosts

    nonisolated(unsafe) private static var hosted: Set<String> = []
    private static let lock = NSLock()

    /// Whether the service hosts this game's phones: Lamp's own serving leaves it to the service (`Store.servesPhonePage`),
    /// so the two never both serve one game. As the service last said, and only while it's on.
    static func hosts(_ app: String) -> Bool { lock.withLock { hosted.contains(app) } }

    private static func setHosted(_ apps: Set<String>) { lock.withLock { hosted = apps } }

    /// The service didn't answer the game (it was turned off in System Settings, or isn't running): Lamp serves it again.
    static func letGo(_ app: String) { lock.withLock { _ = hosted.remove(app) } }

    /// Asks the service which games it has, as Lamp opens and after it's turned on.
    static func refresh() async {
        guard state == .on, let answer = await call(["op": "query"]) else { return setHosted([]) }
        let apps = (answer["installations"] as? [[String: Any]] ?? []).compactMap { $0["installation"] as? String }
        setHosted(Set(apps))
    }

    /// Whether a game built now goes through the service: a Mac game with a phone page, while the service is on.
    static func takes(_ project: LampProject) -> Bool {
        project.platform.target.takesPhones && project.hasMac && !project.onTV && Store.takesPlayers(project) && state == .on
    }

    /// One build of a game for the service: its page as Lamp published it, with Lamp's own library beside it, and a new
    /// key for the game's copy.
    struct Build {
        let snapshot: ControllerSnapshot
        let key: String
        var version: String { snapshot.version }

        /// What the game's copy is told, beside the rest of what Lamp tells it (`Template.installValues`).
        var installValues: [String: String] {
            ["controllers": BackgroundControllers.names.gameService, "controllerVersion": version, "controllerKey": key]
        }
    }

    static func build(for project: LampProject) throws -> Build {
        let page = try ControllerSnapshot.read(TVs.phoneFolder(for: project))
        let files = page.files.filter { $0.path != "lamp-controller.js" }
            + [ControllerSnapshot.File(path: "lamp-controller.js", data: Data(TVTemplate.phoneControllerJS.utf8))]
        let snapshot = ControllerSnapshot(files: files)
        try snapshot.check()
        return Build(snapshot: snapshot, key: ControllerService.newKey())
    }

    /// Hands the service the build, once its copy is signed: the copy's signature is what the game's connection must
    /// show. Returns what went wrong, in words, or nil.
    static func provision(_ build: Build, for project: LampProject, signed app: URL) async -> String? {
        guard let requirement = requirement(of: app) else { return "Lamp couldn't read the game's signature." }
        let request: [String: Any] = ["op": "provision", "installation": project.id, "version": build.version,
                                      "keyVerifier": ControllerService.verifier(of: build.key), "requirement": requirement,
                                      "files": build.snapshot.encoded]
        guard let answer = await call(request) else { return "Lamp couldn't reach its phone controllers service." }
        if let error = answer["error"] as? String { return error }
        lock.withLock { _ = hosted.insert(project.id) }
        return nil
    }

    /// The game is gone: the service ends its session and forgets it.
    static func revoke(_ app: String) async {
        lock.withLock { _ = hosted.remove(app) }
        guard state == .on else { return }
        _ = await call(["op": "revoke", "installation": app])
    }

    static func requirement(of app: URL) -> String? {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
        return text as String
    }

    /// One call to the service, on a connection of its own: nil when the service isn't there or doesn't answer within a
    /// few seconds.
    private static func call(_ request: [String: Any]) async -> [String: Any]? {
        let connection = NSXPCConnection(machServiceName: names.manageService)
        connection.remoteObjectInterface = NSXPCInterface(with: ControllerServiceCalls.self)
        connection.resume()
        defer { connection.invalidate() }
        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            guard let service = connection.remoteObjectProxyWithErrorHandler({ _ in once.resume(nil) }) as? ControllerServiceCalls else {
                return once.resume(nil)
            }
            service.call(ControllerService.encode(request)) { reply in once.resume(ControllerService.decode(reply)) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { once.resume(nil) }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[String: Any]?, Never>?
        init(_ continuation: CheckedContinuation<[String: Any]?, Never>) { self.continuation = continuation }
        func resume(_ value: [String: Any]?) {
            lock.withLock { () -> CheckedContinuation<[String: Any]?, Never>? in defer { continuation = nil }; return continuation }?.resume(returning: value)
        }
    }
}
