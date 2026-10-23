import Foundation

/// A device Lamp has no kit for, declared as data: how to find it, read who it is, set it up, put software on it and
/// look at it. The builder writes one with `device_integration` (the `device-integrations` skill says how), the way an
/// app declares a service that isn't listed with `LampAPI.own`. Nothing in it is code Lamp runs: every step and bridge
/// is a short list of Lamp's own primitives (`IntegrationAction`), each held to what it may reach (`DeviceHTTP`,
/// `DeviceSSH`, `DeviceTools`), and every value put into one is filled by Lamp (`Placeholders`), never by the model.
/// `IntegrationCheck.problems` turns anything else away with plain reasons for the model to fix.
struct Integration: Codable, Hashable {
    /// Lowercase letters, digits and dashes: "roku". Names the file it's kept in and every device found by it.
    var id: String
    /// What people call the device: "Roku".
    var name: String
    var maker: String
    /// The kind of thing it is, in a word or two: "TV", "streaming stick", "photo frame".
    var kind: String?
    var find: [Find]
    var identity: Identity
    var steps: [Step]
    var bridge: Bridge?
    var app: AppKind?
    /// More kinds of app the device takes beside `app`, by a name of the integration's ("game"): each is named to the
    /// naming call as "<id>:<name>" with its `purpose`, and an app made as one keeps that in `LampProject.integration`.
    /// Only Lamp's own kinds, in the integrations Lamp ships: the Xbox's native games (`GameKit`).
    var kinds: [String: AppKind]?
    /// Where what this says was read: the vendor's documentation, a guide.
    var sources: [String]?

    // MARK: Finding it

    /// One way the device announces itself. Exactly one of these is set.
    struct Find: Codable, Hashable {
        /// An SSDP search target ("roku:ecp"); a device that answers it is a match.
        var ssdp: String?
        /// A Bonjour service type ("_googlecast._tcp").
        var bonjour: String?
        /// A USB vendor and product id: refused for now, since Lamp has no way to reach such a device yet.
        var usb: USB?
        /// An HTTP probe of an address the network's SSDP answers named: a port, a path and what the answer holds.
        var http: Probe?
        /// What the SSDP answer's SERVER line, or the Bonjour name, must contain as well.
        var contains: String?

        struct USB: Codable, Hashable { var vendor: Int; var product: Int? }
        struct Probe: Codable, Hashable { var port: Int; var path: String; var contains: String }
    }

    // MARK: Who it is

    /// Where each field of the device's record is read from its own answers. The model says where; Lamp reads it.
    struct Identity: Codable, Hashable {
        /// The device's own software name ("Roku OS"): said once, since it doesn't change from one device to another.
        var os: String
        /// What uniquely names this one device (a serial number, a UDN). Required.
        var id: Read
        var model: Read
        var name: Read?
        var modelID: Read?
        var osVersion: Read?
    }

    /// A value read from one of the device's answers: a request and a path into it.
    struct Read: Codable, Hashable {
        /// A request to the device; or, with `description`, the description its SSDP answer points at.
        var http: Request?
        /// The device's own UPnP description, wherever its SSDP answer says it is now: a description's address can
        /// change with the device's mode (an Xbox's does), which a fixed path would lose.
        var description: Bool?
        /// A JSON path ("device.modelName", "items.0.id") or an XML element ("model-name", "device-info/model-name").
        var json: String?
        var xml: String?
        /// What the value must hold for the device to be this one ("Xbox"): a search answered by other devices too
        /// (a Windows PC sharing media) doesn't make them this kind.
        var contains: String?
    }

    // MARK: Setting it up

    struct Step: Codable, Hashable {
        /// Lowercase letters, digits and dashes, unique in the integration.
        var id: String
        /// The step's name in the list: "Turn on developer mode".
        var title: String
        /// What the person does, in short numbered lines ("Press Home three times").
        var lines: [String]?
        /// Lamp's values shown large: this Mac's address, a code read from the device.
        var show: [Shown]?
        /// A value shown as a QR code for the person to scan.
        var qr: String?
        /// What the person types: a passphrase, a PIN, a password.
        var field: Field?
        /// A page for the person to read. The only form a rooting or jailbreaking step ever takes.
        var link: String?
        /// What the person accepts by doing the step, chosen from Lamp's list; Lamp writes the sentences.
        var accepts: [Acceptance]?
        /// What Lamp does when the person presses the step's button, in order.
        var run: [IntegrationAction]?
        /// The step needs hands on the device: Lamp runs its check until it passes rather than once.
        var wait: Bool?
        /// How Lamp knows the step is done. Every step has one.
        var check: [Condition]
        /// How the step is known. The model may only say it was read (with where); Lamp marks the rest.
        var known: Known?
    }

    struct Shown: Codable, Hashable {
        var label: String
        /// A placeholder Lamp fills: "{mac}", "{address}", or a value read with `read`.
        var value: String
    }

    struct Field: Codable, Hashable {
        /// Lowercase letters, digits and dashes; the step's sequences use it as `{field:<key>}`.
        var key: String
        var label: String
        var secret: Bool?
    }

    /// What doing a step may cost the person. The sentence for each is Lamp's (`IntegrationWords.accepts`), so no
    /// integration can play a risk down.
    enum Acceptance: String, Codable, Hashable, CaseIterable {
        case account, softwareRisk, warranty, dataWiped, updatesStop, protectionsOff, commandRuns
    }

    /// A step is done when every condition holds.
    struct Condition: Codable, Hashable {
        /// A request to the device; the condition holds when it answers 2xx and, with `json` or `xml`, the value read
        /// equals `equals` or contains `contains`.
        var http: Request?
        var json: String?
        var xml: String?
        var equals: String?
        var contains: String?
        /// A TCP port on the device that accepts a connection.
        var tcp: Int?
        /// A field the person has typed and Lamp keeps.
        var field: String?
        /// A vendor sign-in that has come back.
        var signedIn: Bool?
    }

    struct Known: Codable, Hashable {
        enum How: String, Codable, Hashable { case read, people, lamp }
        var how: How
        /// Where it was read, for `read`.
        var source: String?
        /// The model and software version a check passed on, for `people` and `lamp`; Lamp writes them.
        var model: String?
        var version: String?
    }

    // MARK: Putting software on it

    struct Bridge: Codable, Hashable {
        var install: [IntegrationAction]?
        var launch: [IntegrationAction]?
        /// Ends in a request whose answer is kept as the picture (`keep: "picture"`).
        var look: [IntegrationAction]?
        /// Run once per key, with `{key}` the device's name for it from `keys`.
        var use: [IntegrationAction]?
        var logs: [IntegrationAction]?
        /// Ends the app on the device, run before an update replaces it (a device can fail to open a package installed
        /// over its running copy): with the values of the copy that's there.
        var stop: [IntegrationAction]?
        /// Reads the log the app keeps on the device: ends in a request whose answer is kept as the log (`keep: "log"`).
        var log: [IntegrationAction]?
        /// Lamp's names for a remote's keys ("home", "up", "select", "back") to the device's own.
        var keys: [String: String]?
    }

    /// What's built for it: a kind Lamp owns, or one the integration declares.
    struct AppKind: Codable, Hashable {
        /// "tv-web": the TVs' web app; "native-game": a 3D game in C++ on the Xbox (`GameKit`). Lamp's own kinds only.
        var lamp: String?
        var declared: Declared?
        /// What it's for, as the naming call reads it beside the device's name: "a 3D game played with the controller".
        var purpose: String?

        struct Declared: Codable, Hashable {
            /// The scaffold, by path in the app's folder.
            var files: [String: String]
            /// What the builder is told about writing for it.
            var rules: String
            /// The package step, run in the app's sandbox like every build.
            var package: String
            /// Where the package step leaves the package, in the app's folder: what `{package}` names.
            var output: String
            /// A package Lamp makes of the package step's output: "msix", a Windows app package Lamp writes the manifest
            /// for and signs itself (`MSIX`), from a zip of the app's files. `{certificate}`, `{packageFullName}` and
            /// `{appUserModelID}` are then Lamp's values.
            var wrap: String?
            /// The file the app starts at, in a wrapped package: "index.html" unless said.
            var start: String?
            /// Lamp's building blocks the app takes, by library ("web", "brightscript") to where they go in its folder:
            /// Lamp's own files there, written afresh before every turn and build (`DeviceSupport`).
            var support: [String: String]?
            /// A web app's folder, whose index.html Lamp opens at 1920×1080 in a preview on this Mac for the agent's looks and
            /// use (`TVPreview`, as a TV app's), so the builder sees and plays what it makes; Play still puts it on the device.
            var preview: String?
            /// The app's icon on the device, by path in the app's folder to its size in pixels ("images/icon_hd.png":
            /// "336x210"): Lamp draws the icon it made for the app at each, before every turn and build (`DeviceSupport`),
            /// for the files the device's manifest names. The agent never draws one.
            var icons: [String: String]?
        }
    }
}

/// One of Lamp's primitives. Exactly one is set; everything a step or bridge does is one of these.
struct IntegrationAction: Codable, Hashable {
    var http: Request?
    /// "tcp:8060", "ssdp:roku:ecp", "bonjour:_airplay._tcp"
    var probe: String?
    var stream: Stream?
    var ssh: SSH?
    var tool: Tool?
    var vendorSignIn: VendorSignIn?
    /// Waits this many seconds (at most 30) before the next action.
    var wait: Int?
    /// A bridge Lamp ships, by name: "devicectl", "adb", "sdb".
    var bridge: String?

    struct Stream: Codable, Hashable { var port: Int }

    struct SSH: Codable, Hashable {
        var port: Int?
        var user: String
        /// The command, with placeholders Lamp fills and quotes.
        var command: String
        /// What it's for, in plain words for the person's approval.
        var explanation: String
    }

    struct Tool: Codable, Hashable {
        /// A tool on Lamp's list (`DeviceTools.listed`), run as Lamp.
        var name: String?
        /// Or a program to download, run in a sandbox of its own after the person's approval.
        var download: String?
        var sha256: String?
        var arguments: [String]?
        var explanation: String?
    }

    struct VendorSignIn: Codable, Hashable {
        /// The vendor's https page, with `{callback}` where Lamp's loopback address goes.
        var page: String
    }

    static let names = ["http", "probe", "stream", "ssh", "tool", "vendorSignIn", "wait", "bridge"]
}

/// A request to the device. The address is never written: it's the one the device was found at.
struct Request: Codable, Hashable {
    var method: String?
    var port: Int
    var path: String
    var headers: [String: String]?
    var body: String?
    /// A form, sent as multipart; a value "@{package}" is the package's file, "@{certificate}" Lamp's certificate for
    /// a wrapped package.
    var form: [String: String]?
    var auth: Auth?
    /// Over HTTPS, to a device that serves its own certificate (Xbox's Device Portal): Lamp trusts the certificate the
    /// first time and holds the device to it after (`DeviceTLS`).
    var https: Bool?
    /// "picture": the answer is the screen's picture (in a bridge's `look`). "log": the answer is the app's log (in a
    /// bridge's `log`). "key": the answer is a key the device gives this Mac to sign in to it over SSH, kept in Lamp's
    /// folder (in a setup step's `run`).
    var keep: String?
    /// Asks again every two seconds, up to this many seconds, while the device answers 204 (still working): for a
    /// device that takes an install and says later how it went.
    var poll: Int?
    /// What the answer must say for the step to count as done; otherwise the step fails with the answer's words.
    var expect: Expect?

    struct Expect: Codable, Hashable {
        var json: String?
        var xml: String?
        var equals: String?
        var contains: String?
    }

    struct Auth: Codable, Hashable {
        var digest: Bool?
        var user: String
        /// A placeholder for a field the person typed: "{field:password}".
        var password: String
    }
}

// MARK: - Placeholders

/// The values Lamp puts into an integration's requests and commands. The model names them; Lamp fills them, each
/// checked to a safe alphabet, and `field:` values (what the person typed) go only where they can't change what a
/// request or command does: a sign-in, a form's value, a header, a body.
enum Placeholders {
    /// Lamp's own names. `field:<key>` and `read:<step>` are the others.
    static let lamp: Set<String> = ["address", "mac", "package", "appID", "key", "text", "callback", "signIn", "deviceID", "sshKey",
                                    "packageFullName", "appUserModelID"]

    /// Where a placeholder sits, which decides what may go there and how it's written.
    enum Place { case path, command, header, body, auth, form, shown, argument }

    static let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-:/@+=,")

    /// A placeholder is `{name}`, `{field:<key>}` or `{read:<step>}`: a word in braces, nothing else, so a brace that
    /// opens JSON (`{"enabled":true}`) is the template's own text, sent as written.
    private static let pattern = try! NSRegularExpression(pattern: #"\{([A-Za-z][A-Za-z0-9]*(?::[A-Za-z0-9-]+)?)\}"#)

    /// The template in order: its own text, and the placeholders between.
    static func pieces(_ template: String) -> [(text: String, name: String?)] {
        let whole = NSRange(template.startIndex..., in: template)
        var pieces: [(String, String?)] = []
        var at = template.startIndex
        for match in pattern.matches(in: template, range: whole) {
            guard let range = Range(match.range, in: template), let name = Range(match.range(at: 1), in: template) else { continue }
            if at < range.lowerBound { pieces.append((String(template[at..<range.lowerBound]), nil)) }
            pieces.append(("", String(template[name])))
            at = range.upperBound
        }
        if at < template.endIndex { pieces.append((String(template[at...]), nil)) }
        return pieces
    }

    /// Every placeholder in a template.
    static func names(in template: String) -> [String] { pieces(template).compactMap(\.name) }

    /// Why a placeholder can't sit where it is, or nil.
    static func problem(_ name: String, in place: Place, fields: Set<String>) -> String? {
        if name.hasPrefix("field:") {
            let key = String(name.dropFirst("field:".count))
            guard fields.contains(key) else { return "{\(name)} names no field a step asks for" }
            switch place {
            case .auth, .form, .header, .body, .argument: return nil
            case .path, .command, .shown:
                return "{\(name)} can't go in a \(place == .path ? "path" : place == .command ? "command" : "shown value"): what the person types goes only in a sign-in, a form, a header or a body"
            }
        }
        if name.hasPrefix("read:") { return nil }
        // A cookie the device set earlier in the same sequence (a CSRF token), sent back only as a header.
        if name.hasPrefix("cookie:") {
            return place == .header ? nil : "{\(name)} goes only in a header: it's a cookie the device set, sent back to it"
        }
        // One of Lamp's values in base64, as some devices take an id in a query.
        if name.hasPrefix("base64:") {
            let inner = String(name.dropFirst("base64:".count))
            // Only of a value that's not secret: encoding one mustn't carry it past where it may go.
            return lamp.subtracting(["signIn"]).contains(inner) ? nil : "{\(name)} must be base64 of one of Lamp's values that isn't secret, such as {base64:packageFullName}"
        }
        guard lamp.contains(name) else {
            return "{\(name)} isn't a value Lamp fills (they are \(lamp.sorted().map { "{\($0)}" }.joined(separator: ", ")), {field:<key>} and {read:<step>})"
        }
        if name == "signIn", place != .auth, place != .header, place != .form, place != .body {
            return "{signIn} goes only in a sign-in, a header, a form or a body"
        }
        return nil
    }

    struct Unsafe: LocalizedError {
        let name: String
        var errorDescription: String? { "The value for {\(name)} has characters Lamp doesn't send to a device." }
    }

    /// The template with each placeholder filled. A value outside the safe alphabet is refused, except a field's or
    /// a sign-in's, which only reach places that are encoded; in a command each value is quoted for the shell.
    static func fill(_ template: String, _ values: [String: String], in place: Place) throws -> String {
        var out = ""
        for piece in pieces(template) {
            guard let name = piece.name else { out += piece.text; continue }
            let found = name.hasPrefix("base64:") ? values[String(name.dropFirst("base64:".count))].map { Data($0.utf8).base64EncodedString() } : values[name]
            guard let value = found else { throw Unsafe(name: name) }
            // What the person typed, a sign-in and Lamp's public key (which has spaces) aren't held to the alphabet.
            let secret = name.hasPrefix("field:") || name == "signIn" || name == "sshKey"
            if !secret, value.unicodeScalars.contains(where: { !safe.contains($0) }) || value.count > 512 { throw Unsafe(name: name) }
            switch place {
            case .command: out += "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
            case .path: out += value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#+&="))) ?? ""
            default: out += value
            }
        }
        return out
    }
}

// MARK: - Checking one

/// What's wrong with an integration, in plain reasons the model can act on. Empty means Lamp takes it.
enum IntegrationCheck {
    /// `submitted`: from the builder, which may only say a step was read. A file Lamp kept is read with its own marks.
    static func problems(_ data: Data, submitted: Bool = true) -> [String] {
        do {
            let integration = try JSONDecoder().decode(Integration.self, from: data)
            return problems(integration, submitted: submitted)
        } catch let DecodingError.keyNotFound(key, context) {
            return ["\(path(context.codingPath + [key])) is missing."]
        } catch let DecodingError.typeMismatch(_, context) {
            return ["\(path(context.codingPath)) has the wrong type: \(context.debugDescription)"]
        } catch let DecodingError.valueNotFound(_, context) {
            return ["\(path(context.codingPath)) is empty."]
        } catch let DecodingError.dataCorrupted(context) {
            return ["\(context.codingPath.isEmpty ? "The integration" : path(context.codingPath)) can't be read: \(context.debugDescription)"]
        } catch {
            return ["The integration isn't JSON Lamp can read: \(error.localizedDescription)"]
        }
    }

    /// Keys the schema doesn't have: the decoder passes over them, so a misspelt key would otherwise be lost quietly.
    static func unknownKeys(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var found: [String] = []
        func walk(_ value: Any, _ allowed: Shape, _ at: String) {
            switch allowed {
            case .object(let keys):
                guard let object = value as? [String: Any] else { return }
                for (key, child) in object {
                    guard let shape = keys[key] else { found.append("\(at.isEmpty ? key : at + "." + key) isn't part of an integration."); continue }
                    walk(child, shape, at.isEmpty ? key : at + "." + key)
                }
            case .array(let element):
                for (index, child) in (value as? [Any] ?? []).enumerated() { walk(child, element, "\(at)[\(index)]") }
            case .map, .leaf:
                return
            }
        }
        walk(json, Shape.integration, "")
        return found
    }

    indirect enum Shape {
        case object([String: Shape]), array(Shape), map, leaf
        static let request: Shape = .object(["method": .leaf, "https": .leaf, "port": .leaf, "path": .leaf, "headers": .map, "body": .leaf, "form": .map,
                                             "auth": .object(["digest": .leaf, "user": .leaf, "password": .leaf]), "keep": .leaf,
                                             "poll": .leaf, "expect": .object(["json": .leaf, "xml": .leaf, "equals": .leaf, "contains": .leaf])])
        static let action: Shape = .object([
            "http": request, "probe": .leaf, "stream": .object(["port": .leaf]),
            "ssh": .object(["port": .leaf, "user": .leaf, "command": .leaf, "explanation": .leaf]),
            "tool": .object(["name": .leaf, "download": .leaf, "sha256": .leaf, "arguments": .array(.leaf), "explanation": .leaf]),
            "vendorSignIn": .object(["page": .leaf]), "wait": .leaf, "bridge": .leaf,
        ])
        static let appKind: Shape = .object(["lamp": .leaf, "purpose": .leaf, "declared": .object(["files": .map, "rules": .leaf, "package": .leaf, "output": .leaf, "wrap": .leaf, "start": .leaf, "support": .map, "icons": .map, "preview": .leaf])])
        static let read: Shape = .object(["http": request, "description": .leaf, "json": .leaf, "xml": .leaf, "contains": .leaf])
        static let integration: Shape = .object([
            "id": .leaf, "name": .leaf, "maker": .leaf, "kind": .leaf, "sources": .array(.leaf),
            "find": .array(.object(["ssdp": .leaf, "bonjour": .leaf, "contains": .leaf,
                                    "usb": .object(["vendor": .leaf, "product": .leaf]),
                                    "http": .object(["port": .leaf, "path": .leaf, "contains": .leaf])])),
            "identity": .object(["os": .leaf, "id": read, "model": read, "name": read, "modelID": read, "osVersion": read]),
            "steps": .array(.object([
                "id": .leaf, "title": .leaf, "lines": .array(.leaf), "show": .array(.object(["label": .leaf, "value": .leaf])),
                "qr": .leaf, "field": .object(["key": .leaf, "label": .leaf, "secret": .leaf]), "link": .leaf,
                "accepts": .array(.leaf), "run": .array(action), "wait": .leaf,
                "check": .array(.object(["http": request, "json": .leaf, "xml": .leaf, "equals": .leaf, "contains": .leaf,
                                         "tcp": .leaf, "field": .leaf, "signedIn": .leaf])),
                "known": .object(["how": .leaf, "source": .leaf, "model": .leaf, "version": .leaf]),
            ])),
            "bridge": .object(["install": .array(action), "launch": .array(action), "look": .array(action),
                               "use": .array(action), "logs": .array(action), "stop": .array(action), "log": .array(action), "keys": .map]),
            "app": appKind,
            "kinds": .map,
        ])
    }

    /// Word limits for what the person reads on a step's card, as the chat's cards have.
    enum Words {
        static let title = 8
        static let line = 16
        static let lines = 8
        static let label = 6
        static let explanation = 30
    }

    /// The bridges Lamp ships, which an action may name.
    static let bridges: Set<String> = ["devicectl", "adb", "sdb"]

    static func problems(_ integration: Integration, submitted: Bool = true) -> [String] {
        var problems: [String] = []
        func say(_ text: String) { problems.append(text) }

        if !isID(integration.id) { say("id must be lowercase letters, digits and dashes, 2 to 40 of them.") }
        if integration.name.trimmed.isEmpty { say("name is empty.") }
        if integration.maker.trimmed.isEmpty { say("maker is empty.") }
        if integration.find.isEmpty { say("find is empty: say how the device announces itself.") }
        for (index, find) in integration.find.enumerated() {
            let at = "find[\(index)]"
            let set = [find.ssdp != nil, find.bonjour != nil, find.usb != nil, find.http != nil].filter { $0 }.count
            if set != 1 { say("\(at) must have exactly one of ssdp, bonjour or http.") }
            if let ssdp = find.ssdp, ssdp.trimmed.isEmpty || ssdp.contains(where: { $0.isNewline }) || ssdp.count > 120 {
                say("\(at).ssdp must be one search target, such as \"roku:ecp\".")
            }
            if let bonjour = find.bonjour, bonjour.range(of: #"^_[a-z0-9-]{1,40}\._(tcp|udp)$"#, options: .regularExpression) == nil {
                say("\(at).bonjour must be a service type such as \"_airplay._tcp\".")
            }
            // Lamp can't yet reach a device found over USB (no address for its requests), so it isn't taken until it can.
            if find.usb != nil { say("\(at).usb: Lamp doesn't find devices over USB yet; find it on the network.") }
            if let probe = find.http {
                if !isPort(probe.port) { say("\(at).http.port isn't a port.") }
                if let reason = pathProblem(probe.path) { say("\(at).http.path \(reason).") }
                if probe.contains.trimmed.isEmpty { say("\(at).http.contains is empty: say what the answer must hold.") }
            }
        }

        let fields = Set(integration.steps.compactMap { $0.field?.key })
        let steps = Set(integration.steps.map(\.id))

        // Identity
        let identity = integration.identity
        if identity.os.trimmed.isEmpty { say("identity.os is empty: the device's software, such as \"Roku OS\".") }
        for (name, read) in [("id", identity.id), ("model", identity.model)] + [("name", identity.name), ("modelID", identity.modelID), ("osVersion", identity.osVersion)].compactMap({ pair in pair.1.map { (pair.0, $0) } }) {
            let at = "identity.\(name)"
            if (read.json == nil) == (read.xml == nil) { say("\(at) must read the value with exactly one of json or xml.") }
            if (read.http == nil) == (read.description != true) { say("\(at) must read from exactly one of http or description.") }
            if read.description == true, read.xml == nil { say("\(at).description is XML: read it with xml.") }
            if read.description == true, !integration.find.contains(where: { $0.ssdp != nil }) {
                say("\(at).description is the one an SSDP answer points at, so find needs an ssdp entry.")
            }
            if let http = read.http {
                problems += requestProblems(http, at: "\(at).http", fields: [], steps: [])
                if http.method.map({ $0.uppercased() != "GET" }) ?? false { say("\(at).http must be a GET: reading who a device is changes nothing on it.") }
            }
        }

        // Steps
        if integration.steps.isEmpty { say("steps is empty: even a device that needs nothing has a step whose check says it answers.") }
        if steps.count != integration.steps.count { say("Two steps have the same id.") }
        if fields.count != integration.steps.compactMap({ $0.field }).count { say("Two steps ask for a field with the same key.") }
        for (index, step) in integration.steps.enumerated() {
            let at = "steps[\(index)] (\(step.id))"
            if !isID(step.id) { say("\(at).id must be lowercase letters, digits and dashes.") }
            if words(step.title) > Words.title || step.title.trimmed.isEmpty { say("\(at).title must be 1 to \(Words.title) words.") }
            if let lines = step.lines {
                if lines.count > Words.lines { say("\(at).lines has \(lines.count) lines; at most \(Words.lines).") }
                for (n, line) in lines.enumerated() where words(line) > Words.line || line.trimmed.isEmpty {
                    say("\(at).lines[\(n)] must be 1 to \(Words.line) words.")
                }
            }
            for (n, shown) in (step.show ?? []).enumerated() {
                if words(shown.label) > Words.label { say("\(at).show[\(n)].label must be at most \(Words.label) words.") }
                problems += placeholderProblems(shown.value, at: "\(at).show[\(n)].value", place: .shown, fields: fields, steps: steps, needsOne: true)
            }
            if let qr = step.qr { problems += placeholderProblems(qr, at: "\(at).qr", place: .shown, fields: fields, steps: steps, needsOne: true) }
            if let field = step.field {
                if !isID(field.key) { say("\(at).field.key must be lowercase letters, digits and dashes.") }
                if words(field.label) > Words.label || field.label.trimmed.isEmpty { say("\(at).field.label must be 1 to \(Words.label) words.") }
            }
            if let link = step.link, !isWebPage(link) { say("\(at).link must be an https page.") }
            for (n, action) in (step.run ?? []).enumerated() {
                problems += actionProblems(action, at: "\(at).run[\(n)]", fields: fields, steps: steps, inBridge: false)
                if action.http?.keep == "picture" { say("\(at).run[\(n)].http.keep \"picture\" belongs in bridge.look.") }
            }
            if step.check.isEmpty { say("\(at).check is empty: a step is done when Lamp's check passes, never because someone said so.") }
            for (n, condition) in step.check.enumerated() {
                problems += conditionProblems(condition, at: "\(at).check[\(n)]", fields: fields, steps: steps)
            }
            if step.wait == true, step.check.allSatisfy({ $0.field != nil }) {
                say("\(at) waits for hands on the device, so its check must ask the device, not only a field.")
            }
            if let known = step.known {
                if submitted, known.how != .read { say("\(at).known.how can only be \"read\": Lamp marks a step checked or done once its check passes.") }
                if let source = known.source, !isWebPage(source) { say("\(at).known.source must be the https page it was read on.") }
            }
            if (step.accepts ?? []).contains(.commandRuns) == false, step.run?.contains(where: { $0.ssh != nil || ($0.tool != nil && $0.tool?.name == nil) }) == true {
                say("\(at) runs a command on the device or a downloaded tool, so its accepts must include \"commandRuns\".")
            }
        }

        // Bridge
        if let bridge = integration.bridge {
            let sequences: [(String, [IntegrationAction]?)] = [("install", bridge.install), ("launch", bridge.launch), ("look", bridge.look), ("use", bridge.use),
                                                               ("logs", bridge.logs), ("stop", bridge.stop), ("log", bridge.log)]
            for (name, sequence) in sequences {
                for (n, action) in (sequence ?? []).enumerated() {
                    problems += actionProblems(action, at: "bridge.\(name)[\(n)]", fields: fields, steps: steps, inBridge: true)
                    if action.vendorSignIn != nil { say("bridge.\(name)[\(n)]: a sign-in is a setup step, never part of a bridge.") }
                    if let keep = action.http?.keep, !(keep == "picture" && name == "look") && !(keep == "log" && name == "log") {
                        say("bridge.\(name)[\(n)].http.keep: only look keeps an answer, as the picture, and log, as the log.")
                    }
                }
            }
            if let look = bridge.look, !look.contains(where: { $0.http?.keep == "picture" }) {
                say("bridge.look must have a request with keep \"picture\": its answer is the picture.")
            }
            if let log = bridge.log, !log.contains(where: { $0.http?.keep == "log" }) {
                say("bridge.log must have a request with keep \"log\": its answer is the log.")
            }
            if bridge.use != nil, (bridge.keys ?? [:]).isEmpty { say("bridge.use needs keys: Lamp's names for the remote's keys to the device's.") }
            for (key, name) in bridge.keys ?? [:] where !isID(key) || name.unicodeScalars.contains(where: { !Placeholders.safe.contains($0) }) || name.isEmpty {
                say("bridge.keys[\(key)] must map a lowercase name to the device's name for the key, in letters and digits.")
            }
            if bridge.logs?.contains(where: { $0.stream == nil }) == true { say("bridge.logs is a stream, and nothing else.") }
        }

        // App kind
        if let app = integration.app {
            if (app.lamp == nil) == (app.declared == nil) { say("app must have exactly one of lamp or declared.") }
            if let lamp = app.lamp, !["tv-web"].contains(lamp) { say("app.lamp must be one of Lamp's kinds: \"tv-web\".") }
            if let purpose = app.purpose, purpose.trimmed.isEmpty || purpose.count > 120 { say("app.purpose is a few words: what the kind is for.") }
            if let declared = app.declared {
                if declared.files.isEmpty { say("app.declared.files is empty: the scaffold is at least one file.") }
                for path in declared.files.keys + [declared.output] where !isAppPath(path) {
                    say("app.declared: \"\(path)\" must be a plain path inside the app's folder, not in .lamp.")
                }
                if declared.package.trimmed.isEmpty { say("app.declared.package is empty: the command that makes the package.") }
                if declared.rules.trimmed.isEmpty { say("app.declared.rules is empty: what the builder needs to know to write for it.") }
                if let wrap = declared.wrap {
                    if wrap != "msix" { say("app.declared.wrap must be one Lamp makes: \"msix\".") }
                    if !declared.output.lowercased().hasSuffix(".zip") { say("app.declared.output must be a .zip of the app's files when Lamp wraps it.") }
                }
                if let start = declared.start, !isAppPath(start) { say("app.declared.start must be a plain path inside the package.") }
                for (library, path) in declared.support ?? [:] {
                    if DeviceSupport.Library(rawValue: library) == nil {
                        say("app.declared.support: \"\(library)\" isn't one of Lamp's libraries: \(DeviceSupport.Library.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")).")
                    } else if !isAppPath(path) {
                        say("app.declared.support: \"\(path)\" must be a plain path inside the app's folder, not in .lamp.")
                    } else if declared.files.keys.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) {
                        say("app.declared.support: \"\(path)\" is Lamp's, so the scaffold's files can't be there.")
                    }
                }
                if let preview = declared.preview, !isAppPath(preview) {
                    say("app.declared.preview: \"\(preview)\" must be a plain path to a folder inside the app's folder, not in .lamp.")
                }
                for (path, size) in declared.icons ?? [:] {
                    if !isAppPath(path) || !path.lowercased().hasSuffix(".png") {
                        say("app.declared.icons: \"\(path)\" must be a plain path to a .png inside the app's folder, not in .lamp.")
                    } else if declared.files.keys.contains(path) {
                        say("app.declared.icons: \"\(path)\" is Lamp's, so the scaffold's files can't be there.")
                    }
                    if DeviceSupport.iconSize(size) == nil {
                        say("app.declared.icons: \"\(size)\" must be a size in pixels, \"WIDTHxHEIGHT\", each 16 to 4096.")
                    }
                }
            }
            if integration.bridge?.install == nil { say("app is set, so bridge.install must say how it goes on the device.") }
        }
        for (name, kind) in integration.kinds ?? [:] {
            if submitted { say("kinds are Lamp's own and only in the integrations Lamp ships; leave it out."); break }
            if !isID(name) { say("kinds: \"\(name)\" must be lowercase letters, digits and dashes.") }
            if kind.lamp != "native-game" || kind.declared != nil { say("kinds.\(name) must be one of Lamp's own: {\"lamp\": \"native-game\"}.") }
            if kind.purpose?.trimmed.isEmpty != false { say("kinds.\(name).purpose says what it's for, beside app's.") }
            if integration.app?.declared?.wrap != "msix" { say("kinds.\(name): a native game is a Windows package, so app.declared.wrap must be \"msix\" and the bridge must install one.") }
        }
        for source in integration.sources ?? [] where !isWebPage(source) { say("sources: \"\(source)\" isn't an https page.") }
        return problems
    }

    static func actionProblems(_ action: IntegrationAction, at: String, fields: Set<String>, steps: Set<String>, inBridge: Bool) -> [String] {
        var problems: [String] = []
        let set = [action.http != nil, action.probe != nil, action.stream != nil, action.ssh != nil, action.tool != nil,
                   action.vendorSignIn != nil, action.wait != nil, action.bridge != nil].filter { $0 }.count
        if set != 1 { problems.append("\(at) must be exactly one of \(IntegrationAction.names.joined(separator: ", ")).") }
        if let request = action.http { problems += requestProblems(request, at: "\(at).http", fields: fields, steps: steps) }
        if let probe = action.probe {
            let parts = probe.split(separator: ":", maxSplits: 1).map(String.init)
            switch parts.first {
            case "tcp" where parts.count == 2 && Int(parts[1]).map(isPort) == true: break
            case "ssdp" where parts.count == 2 && !parts[1].isEmpty: break
            case "bonjour" where parts.count == 2 && parts[1].hasPrefix("_"): break
            default: problems.append("\(at).probe must be \"tcp:<port>\", \"ssdp:<search target>\" or \"bonjour:<service type>\".")
            }
        }
        if let stream = action.stream, !isPort(stream.port) { problems.append("\(at).stream.port isn't a port.") }
        if let ssh = action.ssh {
            if let port = ssh.port, !isPort(port) { problems.append("\(at).ssh.port isn't a port.") }
            if ssh.user.range(of: #"^[a-z_][a-z0-9_-]{0,31}$"#, options: .regularExpression) == nil { problems.append("\(at).ssh.user must be a plain user name.") }
            if ssh.command.trimmed.isEmpty || ssh.command.count > 1000 { problems.append("\(at).ssh.command must be one command of at most 1000 characters.") }
            if ssh.command.contains(where: { $0.isNewline }) { problems.append("\(at).ssh.command must be one line.") }
            if words(ssh.explanation) > Words.explanation || ssh.explanation.trimmed.isEmpty {
                problems.append("\(at).ssh.explanation must say what it's for in 1 to \(Words.explanation) plain words: the person approves it.")
            }
            problems += placeholderProblems(ssh.command, at: "\(at).ssh.command", place: .command, fields: fields, steps: steps)
        }
        if let tool = action.tool {
            if (tool.name == nil) == (tool.download == nil) { problems.append("\(at).tool must have exactly one of name or download.") }
            if let name = tool.name {
                if let listed = DeviceTools.listed[name] {
                    if tool.arguments != nil { problems.append("\(at).tool: Lamp's list gives \(name) its arguments; leave arguments out.") }
                    for field in listed.fields where !fields.contains(field) { problems.append("\(at).tool: \(name) needs a step that asks for the field \"\(field)\".") }
                } else {
                    problems.append("\(at).tool.name \"\(name)\" isn't on Lamp's list (\(DeviceTools.listed.keys.sorted().joined(separator: ", "))); give download and sha256 to use another.")
                }
            }
            if let download = tool.download {
                if !isWebPage(download) { problems.append("\(at).tool.download must be an https address.") }
                if tool.sha256?.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) == nil { problems.append("\(at).tool.sha256 must be the download's SHA-256, 64 lowercase hex digits.") }
                if words(tool.explanation ?? "") > Words.explanation || (tool.explanation ?? "").trimmed.isEmpty {
                    problems.append("\(at).tool.explanation must say what it's for in 1 to \(Words.explanation) plain words: the person approves it.")
                }
            }
            for (n, argument) in (tool.arguments ?? []).enumerated() {
                problems += placeholderProblems(argument, at: "\(at).tool.arguments[\(n)]", place: .argument, fields: fields, steps: steps)
            }
        }
        if let signIn = action.vendorSignIn {
            if !isWebPage(signIn.page) { problems.append("\(at).vendorSignIn.page must be the vendor's https page.") }
            if !signIn.page.contains("{callback}") { problems.append("\(at).vendorSignIn.page must hold {callback}, where the vendor sends the person back.") }
            for name in Placeholders.names(in: signIn.page) where name != "callback" && name != "deviceID" {
                problems.append("\(at).vendorSignIn.page may only hold {callback} and {deviceID}, not {\(name)}.")
            }
        }
        if let wait = action.wait, !(1...30).contains(wait) { problems.append("\(at).wait is seconds, 1 to 30.") }
        if let bridge = action.bridge, !bridges.contains(bridge) { problems.append("\(at).bridge must be one Lamp ships: \(bridges.sorted().joined(separator: ", ")).") }
        return problems
    }

    static func conditionProblems(_ condition: Integration.Condition, at: String, fields: Set<String>, steps: Set<String>) -> [String] {
        var problems: [String] = []
        let kinds = [condition.http != nil, condition.tcp != nil, condition.field != nil, condition.signedIn != nil].filter { $0 }.count
        if kinds != 1 { problems.append("\(at) must have exactly one of http, tcp, field or signedIn.") }
        if let request = condition.http {
            problems += requestProblems(request, at: "\(at).http", fields: fields, steps: steps)
            if (condition.equals != nil || condition.contains != nil), condition.json == nil, condition.xml == nil {
                problems.append("\(at) compares a value, so it must read it with json or xml.")
            }
            if condition.json != nil, condition.xml != nil { problems.append("\(at) reads with json or xml, not both.") }
        } else if condition.json != nil || condition.xml != nil || condition.equals != nil || condition.contains != nil {
            problems.append("\(at): json, xml, equals and contains go with http.")
        }
        if let port = condition.tcp, !isPort(port) { problems.append("\(at).tcp isn't a port.") }
        if let field = condition.field, !fields.contains(field) { problems.append("\(at).field names no field a step asks for.") }
        return problems
    }

    static func requestProblems(_ request: Request, at: String, fields: Set<String>, steps: Set<String>) -> [String] {
        var problems: [String] = []
        if !isPort(request.port) { problems.append("\(at).port isn't a port.") }
        if let method = request.method, !["GET", "POST", "PUT", "DELETE"].contains(method.uppercased()) {
            problems.append("\(at).method must be GET, POST, PUT or DELETE.")
        }
        if let reason = pathProblem(request.path) { problems.append("\(at).path \(reason).") }
        problems += placeholderProblems(request.path, at: "\(at).path", place: .path, fields: fields, steps: steps)
        if request.form != nil, request.body != nil { problems.append("\(at) sends a form or a body, not both.") }
        for (name, value) in request.headers ?? [:] {
            if name.range(of: #"^[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) == nil { problems.append("\(at).headers: \"\(name)\" isn't a header name.") }
            if ["host", "authorization", "cookie", "proxy-authorization"].contains(name.lowercased()) && !value.contains("{") {
                problems.append("\(at).headers: \(name) is Lamp's to set.")
            }
            if name.lowercased() == "host" { problems.append("\(at).headers: Host is always the device's.") }
            problems += placeholderProblems(value, at: "\(at).headers.\(name)", place: .header, fields: fields, steps: steps)
        }
        if let body = request.body { problems += placeholderProblems(body, at: "\(at).body", place: .body, fields: fields, steps: steps) }
        for (name, value) in request.form ?? [:] {
            if value.hasPrefix("@"), value != "@{package}", value != "@{certificate}" {
                problems.append("\(at).form.\(name): the only files a form sends are \"@{package}\" and, for a wrapped package, \"@{certificate}\".")
            }
            if !value.hasPrefix("@") { problems += placeholderProblems(value, at: "\(at).form.\(name)", place: .form, fields: fields, steps: steps) }
        }
        if let auth = request.auth {
            if auth.user.unicodeScalars.contains(where: { !Placeholders.safe.contains($0) }) || auth.user.isEmpty { problems.append("\(at).auth.user must be a plain name.") }
            let names = Placeholders.names(in: auth.password)
            if names.count != 1 || "{\(names[0])}" != auth.password || !(names[0].hasPrefix("field:") || names[0] == "signIn") {
                problems.append("\(at).auth.password must be one placeholder for what the person typed: \"{field:<key>}\".")
            } else {
                problems += placeholderProblems(auth.password, at: "\(at).auth.password", place: .auth, fields: fields, steps: steps)
            }
        }
        if let keep = request.keep, !["picture", "log", "key"].contains(keep) { problems.append("\(at).keep can only be \"picture\", \"log\" or \"key\".") }
        if let poll = request.poll, !(2...600).contains(poll) { problems.append("\(at).poll is seconds, 2 to 600.") }
        if let expect = request.expect {
            if (expect.json == nil) == (expect.xml == nil) { problems.append("\(at).expect reads the answer with exactly one of json or xml.") }
            if (expect.equals == nil) == (expect.contains == nil) { problems.append("\(at).expect needs exactly one of equals or contains.") }
        }
        return problems
    }

    static func placeholderProblems(_ template: String, at: String, place: Placeholders.Place, fields: Set<String>, steps: Set<String>, needsOne: Bool = false) -> [String] {
        var problems: [String] = []
        let names = Placeholders.names(in: template)
        if needsOne, names.isEmpty { problems.append("\(at) must be a value Lamp fills, such as \"{mac}\": Lamp shows only its own values.") }
        for name in names {
            if let reason = Placeholders.problem(name, in: place, fields: fields) { problems.append("\(at): \(reason).") }
            if name.hasPrefix("read:"), !steps.contains(String(name.dropFirst("read:".count))) {
                problems.append("\(at): {\(name)} names no step.")
            }
        }
        return problems
    }

    static func pathProblem(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.hasPrefix("//") else { return "must start with one /" }
        if path.contains("..") { return "can't hold .." }
        if path.contains("://") || path.contains("@") || path.contains("#") || path.contains("\\") { return "must be a path on the device, not an address" }
        if path.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) {
            return "can't hold spaces"
        }
        return nil
    }

    static func isID(_ text: String) -> Bool { text.range(of: #"^[a-z0-9][a-z0-9-]{1,39}$"#, options: .regularExpression) != nil }
    static func isPort(_ port: Int) -> Bool { (1...65535).contains(port) }
    static func isWebPage(_ text: String) -> Bool {
        guard let url = URL(string: text), url.scheme == "https", let host = url.host, host.contains("."), url.user == nil else { return false }
        return true
    }
    static func isAppPath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.hasPrefix(".") && !path.contains("..") && !path.contains("\\")
            && !path.split(separator: "/").contains { $0.hasPrefix(".") } && path.count < 200
    }
    static func words(_ text: String) -> Int { text.split(whereSeparator: { $0.isWhitespace }).count }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().trimmingPrefix(".").description
    }
}
