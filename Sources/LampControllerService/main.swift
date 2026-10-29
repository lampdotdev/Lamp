import Foundation
import LampRelayKit
import Security

// Phones as controllers for a game on this Mac while Lamp is closed (`ControllerService`, `ControllerHost`): a launch
// agent in Lamp's bundle, which Lamp registers with macOS when the person turns it on (`SMAppService.agent`), and macOS
// starts at login and keeps running until they turn it off. It listens on two XPC names from its plist: one for Lamp,
// let in only when it's the Lamp this service came in, and one for the games Lamp gave it, each held to its own
// signature once it says which game it is.

/// The Lamp this service is part of: the app three folders up (Lamp.app/Contents/Helpers/LampControllerService).
let lampBundle = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let bundleID = Bundle(url: lampBundle)?.bundleIdentifier ?? "dev.lamp.host"
let names = ControllerService.Names(bundleID: bundleID)
let host = ControllerHost(names: names, folder: names.folder())
host.onChange = { app, open in NSLog("%@", "\(app): session \(open ? "open" : "ended")") }

/// What Lamp's own signature requires: only that program may hand the service games or take them away.
func lampRequirement() -> String? {
    var code: SecStaticCode?
    var requirement: SecRequirement?
    var text: CFString?
    guard SecStaticCodeCreateWithPath(lampBundle as CFURL, [], &code) == errSecSuccess, let code,
          SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement,
          SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
    return text as String
}

final class Management: NSObject, NSXPCListenerDelegate, ControllerServiceCalls {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ControllerServiceCalls.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func call(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        reply(ControllerService.encode(host.manage(ControllerService.decode(request))))
    }
}

/// One game's connection: it says first which game and build it is (`hello`), and from then on every message on it must
/// come from a program with that build's signature, or the system ends the connection; only then does it get its
/// session (`open`).
final class GameConnection: NSObject, ControllerServiceCalls {
    private let id: Int
    private weak var connection: NSXPCConnection?
    private let lock = NSLock()
    private var bound: (installation: String, version: String)?

    init(id: Int, connection: NSXPCConnection) {
        self.id = id
        self.connection = connection
    }

    func call(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        let message = ControllerService.decode(request)
        let installation = message["installation"] as? String ?? "", version = message["version"] as? String ?? ""
        switch message["op"] as? String {
        case "hello":
            let answer: [String: Any] = lock.withLock {
                if let bound { return bound == (installation, version) ? ["protocol": ControllerService.protocolVersion, "epoch": host.epoch]
                                                                        : ["status": 403, "error": "This connection is another game's."] }
                guard let requirement = host.requirement(installation: installation, version: version) else {
                    return ["status": 404, "error": "Lamp didn't set up phone controllers for this copy of the game. Open the game from Lamp to update it."]
                }
                connection?.setCodeSigningRequirement(requirement)
                bound = (installation, version)
                return ["protocol": ControllerService.protocolVersion, "epoch": host.epoch]
            }
            reply(ControllerService.encode(answer))
        case "open":
            guard let bound = lock.withLock({ bound }), bound == (installation, version) else {
                return reply(ControllerService.encode(["status": 403, "error": "Say which game this is first."]))
            }
            reply(ControllerService.encode(host.open(installation: installation, version: version, key: message["key"] as? String ?? "", connection: id)))
        default:
            reply(ControllerService.encode(["status": 404, "error": "This service doesn't know that call."]))
        }
    }
}

final class Games: NSObject, NSXPCListenerDelegate {
    private let lock = NSLock()
    private var next = 0

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let id = lock.withLock { next += 1; return next }
        connection.exportedInterface = NSXPCInterface(with: ControllerServiceCalls.self)
        connection.exportedObject = GameConnection(id: id, connection: connection)
        connection.invalidationHandler = { host.closed(connection: id) }
        connection.interruptionHandler = { host.closed(connection: id) }
        connection.resume()
        return true
    }
}

guard let requirement = lampRequirement() else {
    NSLog("%@", "The service couldn't read Lamp's signature at \(lampBundle.path).")
    exit(1)
}
let management = Management(), games = Games()
let manageListener = NSXPCListener(machServiceName: names.manageService)
manageListener.setConnectionCodeSigningRequirement(requirement)
manageListener.delegate = management
manageListener.resume()
let gameListener = NSXPCListener(machServiceName: names.gameService)
gameListener.delegate = games
gameListener.resume()
NSLog("%@", "Phone controllers for \(names.lampName): listening as \(names.label), epoch \(host.epoch)")
dispatchMain()
