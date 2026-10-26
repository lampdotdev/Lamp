import AppKit
import Foundation

/// The integrations Lamp has (`Integration`), the devices found by them, and the devices on the network Lamp doesn't
/// know yet. An integration the builder hands Lamp (`device_integration`) is kept in Lamp's folder once it's checked;
/// those Lamp ships go in `Resources/Devices`. A device found by one is shown for the moment, and kept (with the steps
/// done on it) only once a setup step's check has passed on it: a neighbour's device may answer a scan too.
enum Integrations {
    static let folder = Edition.supportFolder.appendingPathComponent("Integrations")
    private static var keptURL: URL { DeviceFolder.root.appendingPathComponent("kept.json") }
    private static let lock = NSLock()

    // MARK: The integrations

    private static var shippedFolder: URL? { Bundle.main.resourceURL?.appendingPathComponent("Devices") }

    /// The person's, and Lamp's own (shipped), which win: a written integration never stands in for one Lamp checked.
    static func all() -> [Integration] {
        var byID: [String: Integration] = [:]
        for (folder, shipped) in [(folder, false), (shippedFolder, true)] {
            guard let folder else { continue }
            for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "json" {
                // One written on this Mac is checked again as it's read: the file is in Lamp's folder, but a later Lamp
                // may hold integrations to more than the one that took it.
                guard let data = try? Data(contentsOf: file), shipped || IntegrationCheck.problems(data, submitted: false).isEmpty,
                      let integration = try? JSONDecoder().decode(Integration.self, from: data) else { continue }
                byID[integration.id] = integration
            }
        }
        return byID.values.sorted { $0.name < $1.name }
    }

    static func isShipped(_ id: String) -> Bool {
        shippedFolder.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(id + ".json").path) } ?? false
    }

    static func integration(_ id: String) -> Integration? { all().first { $0.id == id } }

    /// Checks an integration the builder wrote and keeps it when nothing's wrong. What Lamp already knows of a step
    /// (it was checked on a device, or done by people) stays with the step while the step is unchanged; any other
    /// step is marked as read, never as tried.
    static func submit(_ data: Data) -> (integration: Integration?, problems: [String]) {
        var problems = IntegrationCheck.unknownKeys(data) + IntegrationCheck.problems(data)
        guard problems.isEmpty, var integration = try? JSONDecoder().decode(Integration.self, from: data) else {
            if problems.isEmpty { problems = ["The integration couldn't be read."] }
            return (nil, problems)
        }
        if isShipped(integration.id) { return (nil, ["id \"\(integration.id)\" is one Lamp ships; choose another."]) }
        let before = self.integration(integration.id)
        for index in integration.steps.indices {
            var step = integration.steps[index]
            let source = step.known?.source
            step.known = nil
            if let old = before?.steps.first(where: { $0.id == step.id }), let known = old.known, known.how != .read {
                var plain = old
                plain.known = nil
                if plain == step { step.known = known; integration.steps[index] = step; continue }
            }
            step.known = Integration.Known(how: .read, source: source)
            integration.steps[index] = step
        }
        // A test run's mark stays with a bridge that hasn't changed.
        if let known = before?.bridge?.known, before?.bridge?.unmarked == integration.bridge?.unmarked { integration.bridge?.known = known }
        write(integration)
        return (integration, [])
    }

    static func write(_ integration: Integration) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(integration).write(to: folder.appendingPathComponent(integration.id + ".json"), options: .atomic)
    }

    /// A step's check passed on a device of this model and software: Lamp marks how it's known now. A step that needed
    /// the person's hands on the device is done by people; one Lamp did itself is checked by Lamp. `model` is the
    /// device's as it's known now, which a model step may just have read. A shipped integration's marks are Lamp's to
    /// write in the repository: a copy here would never be read, since the shipped one wins.
    static func mark(_ stepID: String, of integrationID: String, model: String, version: String) {
        guard !isShipped(integrationID), var integration = integration(integrationID),
              let index = integration.steps.firstIndex(where: { $0.id == stepID }) else { return }
        let step = integration.steps[index]
        let hands = step.wait == true || !(step.lines ?? []).isEmpty || step.field != nil
        let how: Integration.Known.How = hands ? .people : .lamp
        if step.known?.how == .lamp, how == .people { return }
        integration.steps[index].known = Integration.Known(how: how, source: step.known?.source, model: model, version: version)
        write(integration)
    }

    /// Takes away copies of shipped integrations an earlier Lamp marked into the person's folder. Each was shadowed by
    /// the shipped one, so nothing read it; left, an old copy would stand in if Lamp ever stopped shipping that id.
    static func dropShippedCopies() {
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where file.pathExtension == "json" && isShipped(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Devices kept

    /// A device found by an integration that has had a setup step pass: proven the person's.
    struct Kept: Codable, Hashable {
        var id: String
        var integration: String
        var name: String
        var model: String
        var modelID: String
        var os: String
        var osVersion: String
        var address: String
        var passed: [String] = []
        /// Values read by steps, for `{read:<step>}`.
        var reads: [String: String] = [:]
    }

    static func kept() -> [Kept] {
        lock.lock(); defer { lock.unlock() }
        return (try? Data(contentsOf: keptURL)).flatMap { try? JSONDecoder().decode([Kept].self, from: $0) } ?? []
    }

    static func keep(_ device: Kept) {
        lock.lock(); defer { lock.unlock() }
        var all = (try? Data(contentsOf: keptURL)).flatMap { try? JSONDecoder().decode([Kept].self, from: $0) } ?? []
        all.removeAll { $0.id == device.id }
        all.append(device)
        try? FileManager.default.createDirectory(at: DeviceFolder.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? JSONEncoder().encode(all).write(to: keptURL, options: .atomic)
    }

    static func kept(_ id: String) -> Kept? { kept().first { $0.id == id } }

    /// A kept device's model: what its integration's model step read on it, else what it said of itself when it was found.
    static func model(of kept: Kept) -> String { readModel(of: kept) ?? kept.model }

    /// What a kept device's model step read on it: nil before that step has passed, or when its integration has none.
    static func readModel(of kept: Kept) -> String? { readModel(of: kept, by: integration(kept.integration)) }

    static func readModel(of kept: Kept, by integration: Integration?) -> String? {
        guard let step = integration?.steps.first(where: { $0.model == true }) else { return nil }
        return kept.reads[step.id]?.trimmed.nilIfEmpty
    }

    /// Forgets a device Lamp set up, as the person asks in Settings: its record and what it read, the certificates kept for
    /// it and the keys in its folder, what was typed for it, and the commands approved on it. Found on the network
    /// again, it's a device to set up from the start.
    static func forget(_ id: String) {
        lock.lock()
        var all = (try? Data(contentsOf: keptURL)).flatMap { try? JSONDecoder().decode([Kept].self, from: $0) } ?? []
        all.removeAll { $0.id == id }
        try? JSONEncoder().encode(all).write(to: keptURL, options: .atomic)
        lock.unlock()
        try? FileManager.default.removeItem(at: DeviceFolder.of(id))
        DeviceFields.forget(device: id)
        DeviceApprovals.forget(id)
    }

    /// Starts a kept device's setup over, for Reconnect: its steps are to be done again, the first sign-in included, so
    /// nothing secret goes to it before its new certificate has been kept.
    static func startOver(_ id: String) {
        guard var device = kept(id) else { return }
        device.passed = []
        device.reads = [:]
        keep(device)
    }

    /// The step a device is at: the first whose check hasn't passed on it. Nil when it's set up.
    static func next(for device: Device) -> Integration.Step? {
        guard let id = device.integration, let integration = integration(id) else { return nil }
        let passed = Set(kept(device.id)?.passed ?? [])
        return integration.steps.first { !passed.contains($0.id) }
    }

    // MARK: Finding

    /// What the network said, once per look, for every integration and the unknown devices to share.
    struct Scan {
        let answers: [DeviceProbe.SSDPAnswer]
    }

    /// The devices every integration finds now, the kept ones that aren't on the network now, and the devices that
    /// answered the scan that nothing Lamp has knows (`known` are the addresses Lamp's kits found themselves).
    static func devices(known: Set<String>) async -> [Device] {
        let integrations = all()
        let scan = Scan(answers: await DeviceProbe.ssdp("ssdp:all", seconds: 2.5))
        var found: [Device] = []
        for integration in integrations {
            for address in await addresses(for: integration, scan: scan) where !found.contains(where: { $0.address == address }) {
                if let device = await identify(integration, at: address) { found.append(device) }
            }
        }
        // One found a moment ago that missed this scan (SSDP is a shout, and a busy device misses some) is still here.
        for device in recentlyFound() where !found.contains(where: { $0.id == device.id }) { found.append(device) }
        // A kept device not found now keeps what was known of it, at its last address.
        for keptOne in kept() where !found.contains(where: { $0.id == keptOne.id }) {
            found.append(device(from: keptOne, onNetwork: false))
        }
        for index in found.indices {
            if var keptOne = kept(found[index].id), keptOne.address != found[index].address, found[index].connected {
                keptOne.address = found[index].address ?? keptOne.address
                keep(keptOne)
            }
        }
        let taken = known.union(found.compactMap(\.address))
        return found + (await unknown(scan, except: taken))
    }

    /// Where an integration's device answers on the network now.
    static func addresses(for integration: Integration, scan: Scan) async -> [String] {
        var addresses: [String] = []
        for find in integration.find {
            if let target = find.ssdp {
                let answers = target == "ssdp:all" ? scan.answers : await DeviceProbe.ssdp(target, seconds: 3)
                addresses += answers.filter { $0.searchTarget.lowercased() == target.lowercased() || target == "ssdp:all" }
                    .filter { answer in find.contains.map { answer.server.localizedCaseInsensitiveContains($0) } ?? true }
                    .map(\.address)
            }
            if let type = find.bonjour {
                addresses += await DeviceProbe.bonjour(type)
                    .filter { found in find.contains.map { found.name.localizedCaseInsensitiveContains($0) } ?? true }
                    .map(\.address)
            }
            if let probe = find.http {
                for address in Set(scan.answers.map(\.address)) where DeviceAddress.isPrivate(address) {
                    let request = Request(port: probe.port, path: probe.path)
                    if let answer = try? await DeviceHTTP.send(request, to: address, values: [:]), answer.ok, answer.text.contains(probe.contains) {
                        addresses.append(address)
                    }
                }
            }
        }
        return Array(Set(addresses.filter(DeviceAddress.isPrivate))).sorted()
    }

    /// The devices integrations found in the last few minutes, by id: shown until a scan has missed them for that long.
    nonisolated(unsafe) private static var recent: [String: (device: Device, at: Date)] = [:]

    static func recentlyFound() -> [Device] {
        lock.lock(); defer { lock.unlock() }
        recent = recent.filter { $0.value.at > Date().addingTimeInterval(-600) }
        return recent.values.map(\.device)
    }

    /// Where the device at an address says its UPnP description is now, from its answer to the integration's own SSDP
    /// search: only a description on the device itself, over plain HTTP.
    static func describedAt(_ address: String, by integration: Integration) async -> Request? {
        for target in integration.find.compactMap(\.ssdp) {
            for answer in await DeviceProbe.ssdp(target) where answer.address == address {
                guard let location = answer.location, let url = URL(string: location), url.scheme == "http", url.host == address else { continue }
                return Request(port: url.port ?? 80, path: (url.path.isEmpty ? "/" : url.path) + (url.query.map { "?" + $0 } ?? ""))
            }
        }
        return nil
    }

    /// The device at an address, read from its own answers as the integration says. Nil when it doesn't answer as one.
    static func identify(_ integration: Integration, at address: String) async -> Device? {
        var answers: [Request: DeviceHTTP.Answer] = [:]
        var description: Request??
        func read(_ read: Integration.Read?) async -> String? {
            guard let read else { return nil }
            var request = read.http
            if read.description == true {
                if description == nil { description = await describedAt(address, by: integration) }
                request = description ?? nil
            }
            guard let request else { return nil }
            if answers[request] == nil, let answer = try? await DeviceHTTP.send(request, to: address, values: [:]), answer.ok {
                answers[request] = answer
            }
            let value = answers[request].flatMap { DeviceHTTP.value(json: read.json, xml: read.xml, in: $0) }?.trimmed.nilIfEmpty
            if let needed = read.contains, !(value ?? "").localizedCaseInsensitiveContains(needed) { return nil }
            return value
        }
        let identity = integration.identity
        guard let serial = await read(identity.id), var model = await read(identity.model) else { return nil }
        let id = "\(integration.id):\(serial)"
        if let keptOne = kept(id) { model = Integrations.model(of: keptOne) }
        var device = Device(id: id, kind: .other, maker: integration.maker, model: model, modelID: await read(identity.modelID) ?? "",
                            name: await read(identity.name) ?? "\(integration.maker) \(model)", os: identity.os,
                            osVersion: await read(identity.osVersion) ?? "", reach: .network)
        device.integration = integration.id
        device.address = address
        lock.lock()
        recent[id] = (device, Date())
        lock.unlock()
        if var keptOne = kept(id) {
            keptOne.name = device.name
            keptOne.osVersion = device.osVersion
            keep(keptOne)
        }
        return device
    }

    static func device(from kept: Kept, onNetwork: Bool) -> Device {
        var device = Device(id: kept.id, kind: .other, maker: integration(kept.integration)?.maker ?? "", model: model(of: kept), modelID: kept.modelID,
                            name: kept.name, os: kept.os, osVersion: kept.osVersion, reach: .network)
        device.integration = kept.integration
        device.address = kept.address
        device.connected = onNetwork
        return device
    }

    /// A device that answered the scan, from the UPnP descriptions its answers point at. A device often answers for
    /// several services, each with a description of its own, and the first to answer may say nothing of the device
    /// (a TV's Netflix service answers a few bytes of "status=ok"), so each is tried until one names it. `send` is how
    /// a description is read; tests answer with recorded ones.
    static func described(_ address: String, answers: [DeviceProbe.SSDPAnswer],
                          send: (Request, String) async -> DeviceHTTP.Answer? = { try? await DeviceHTTP.send($0, to: $1, values: [:]) }) async -> Device? {
        var locations: [String] = []
        for location in answers.compactMap(\.location) where !locations.contains(location) && URL(string: location)?.host == address { locations.append(location) }
        for location in locations {
            guard let url = URL(string: location), url.scheme == "http",
                  let answer = await send(Request(port: url.port ?? 80, path: url.path.isEmpty ? "/" : url.path + (url.query.map { "?" + $0 } ?? "")), address),
                  answer.ok else { continue }
            let name = DeviceHTTP.xml("friendlyName", in: answer.body)
            let maker = DeviceHTTP.xml("manufacturer", in: answer.body) ?? ""
            let model = DeviceHTTP.xml("modelName", in: answer.body) ?? DeviceHTTP.xml("modelDescription", in: answer.body) ?? ""
            let type = DeviceHTTP.xml("deviceType", in: answer.body) ?? ""
            // Routers and other plumbing answer every scan; nobody makes apps for them.
            if type.contains("InternetGatewayDevice") || type.contains("WANDevice") || type.contains("WFADevice") { return nil }
            guard let name, !maker.isEmpty || !model.isEmpty else { continue }
            var device = Device(id: "found:\(address)", kind: .other, maker: maker, model: model.isEmpty ? maker : model,
                                modelID: DeviceHTTP.xml("modelNumber", in: answer.body) ?? "", name: name, os: "", osVersion: "", reach: .network)
            device.address = address
            device.discovery = answers.map { "\($0.searchTarget) (\($0.server))" }.joined(separator: "; ")
            return device
        }
        return nil
    }

    /// The devices that answered the scan and that nothing Lamp has knows: each read from its own UPnP description
    /// when it has one, shown for the moment with Set Up…, and never kept.
    static func unknown(_ scan: Scan, except taken: Set<String>) async -> [Device] {
        var byAddress: [String: [DeviceProbe.SSDPAnswer]] = [:]
        for answer in scan.answers where !taken.contains(answer.address) && DeviceAddress.isPrivate(answer.address) {
            byAddress[answer.address, default: []].append(answer)
        }
        // This Mac answers too, for its own services.
        for address in TVs.macAddresses() { byAddress[address] = nil }
        var devices: [Device] = []
        for (address, answers) in byAddress {
            if let device = await described(address, answers: answers) { devices.append(device) }
        }
        return devices.sorted { $0.name < $1.name }
    }
}

// MARK: - Running an integration

/// Runs an integration's steps and sequences on one device, with Lamp's values filled in and each primitive held to
/// its guard. A command on the device or a downloaded tool runs only once `approve` has said yes for its exact text.
struct IntegrationRunner {
    let integration: Integration
    let device: Device
    /// Asks the person about a command or tool not yet approved on this device; true to run it.
    var approve: (DeviceCommandApproval) async -> Bool = { _ in false }
    /// A line for the app's log, from a stream.
    var onLog: (@Sendable (String) -> Void)?
    /// How a step's check reaches the device; tests answer for a made-up one.
    var send: (Request, String, [String: String], DeviceTLS.Pins?) async throws -> DeviceHTTP.Answer = {
        try await DeviceHTTP.send($0, to: $1, values: $2, pins: $3)
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// What a sequence gave back: a picture from a look, a stream that's running.
    struct Outcome {
        var picture: Data?
        /// The app's log, from a bridge's `log` (`keep: "log"`).
        var log: String?
        var streams: [DeviceStream] = []
        var printed: [String] = []
        /// What each request that kept nothing was answered, as text: where a device says what it made of a package.
        var answers: [String] = []
    }

    var address: String {
        get throws {
            guard let address = device.address, DeviceAddress.isPrivate(address) else {
                throw Failure(message: "Lamp doesn't know where \(device.name) is on your network. Make sure it's on, then look for devices again.")
            }
            return address
        }
    }

    /// Lamp's values for this device, and the caller's (a package, an app id, a key). Without `secrets`, nothing the
    /// person typed or a sign-in returned.
    func values(_ extra: [String: String] = [:], secrets: Bool = true) -> [String: String] {
        var values = extra
        values["address"] = device.address
        values["deviceID"] = device.id.split(separator: ":").dropFirst().joined(separator: ":")
        values["mac"] = Self.macAddress(near: device.address)
        if let key = DeviceSSH.publicKey { values["sshKey"] = key }
        if secrets {
            for step in integration.steps {
                if let field = step.field, let value = DeviceFields.read(field.key, device: device.id) { values["field:" + field.key] = value }
            }
            if let signIn = DeviceFields.read("signIn", device: device.id) { values["signIn"] = signIn }
        }
        for (step, value) in Integrations.kept(device.id)?.reads ?? [:] { values["read:" + step] = value }
        return values
    }

    /// This Mac's address on the device's network: the one that shares the most of its leading digits.
    static func macAddress(near address: String?) -> String? {
        let mine = TVs.macAddresses()
        guard let address else { return mine.first }
        func shared(_ a: String) -> Int { zip(a.split(separator: "."), address.split(separator: ".")).prefix { $0 == $1 }.count }
        return mine.max { shared($0) < shared($1) }
    }

    /// Whether anything in the integration shows or sends Lamp's public key, which is made the first time it's needed.
    var needsSSHKey: Bool {
        guard let data = try? JSONEncoder().encode(integration) else { return false }
        return Placeholders.names(in: String(decoding: data, as: UTF8.self)).contains("sshKey")
    }

    /// Makes what Lamp's own values need before they're read: its SSH key, which a step may show or send before any
    /// command has run.
    func prepare() async {
        if needsSSHKey, DeviceSSH.publicKey == nil { _ = try? await DeviceSSH.ensureKey() }
    }

    /// The first time the device's certificate is kept for a port, the root the integration says signs it is read from
    /// the device over that same connection and kept with it (`DeviceTLS.Pins.keepRoot`), so a certificate the device
    /// makes later is still known as its own.
    func learnRoot(_ request: Request, _ answer: DeviceHTTP.Answer) async {
        guard request.https == true, let path = integration.certificateRoot, let leaf = answer.certificate else { return }
        let pins = DeviceTLS.Pins(deviceID: device.id)
        guard pins.root(port: request.port) == nil, let address = try? address else { return }
        let fetch = Request(port: request.port, path: path, https: true)
        guard let got = try? await DeviceHTTP.send(fetch, to: address, values: [:], pins: pins), got.ok,
              let root = DeviceTLS.certificate(from: got.body) else { return }
        pins.keepRoot(root, signing: leaf, port: request.port)
    }

    /// Runs a sequence in order, stopping at the first failure. Settings it changed only for itself (`restore`) are put
    /// back as it ends, however it ends; or, given `changed`, once the caller is done with them (`putBack`): an Xbox
    /// settles an installed package's type only as it's opened, after the install's own sequence.
    func run(_ sequence: [IntegrationAction], extra: [String: String] = [:], files: [String: URL] = [:],
             changed: ChangedSettings? = nil) async throws -> Outcome {
        await prepare()
        let settings = changed ?? ChangedSettings()
        // Two sequences changing a device's setting at once would each put back what the other set.
        if sequence.contains(where: { $0.http?.restore != nil }), !settings.held {
            await SettingChanges.shared.begin(device.id)
            settings.held = true
        }
        let result: Result<Outcome, Error>
        do { result = .success(try await run(sequence, extra: extra, files: files, changed: settings)) } catch { result = .failure(error) }
        if changed == nil { await putBack(settings) }
        return try result.get()
    }

    /// Settings sequences changed for themselves, until `putBack` puts them as they were.
    final class ChangedSettings {
        fileprivate var restores: [Restore] = []
        fileprivate var held = false
    }

    /// Each setting as it was before a sequence changed it, last changed first, sent with the values (the CSRF cookie)
    /// its change went with. A device that can't be reached by then keeps what the sequence set: there's nothing more
    /// to do from here.
    func putBack(_ changed: ChangedSettings) async {
        for restore in changed.restores.reversed() {
            guard let field = restore.request.restore, let body = try? JSONSerialization.data(withJSONObject: [field: restore.was]) else { continue }
            var back = restore.request
            back.body = String(decoding: body, as: UTF8.self)
            let answer = try? await DeviceHTTP.send(back, to: try address, values: restore.values, pins: DeviceTLS.Pins(deviceID: device.id))
            if answer?.ok != true { onLog?("Lamp couldn't set \(restore.request.path) on \(device.name) back to \(restore.was).") }
        }
        changed.restores = []
        if changed.held {
            changed.held = false
            await SettingChanges.shared.end(device.id)
        }
    }

    fileprivate struct Restore { let request: Request; let was: String; let values: [String: String] }

    /// The devices whose settings a sequence has changed for itself and not yet put back.
    private actor SettingChanges {
        static let shared = SettingChanges()
        private var busy: Set<String> = []

        func begin(_ id: String) async {
            while busy.contains(id) { try? await Task.sleep(for: .milliseconds(200)) }
            busy.insert(id)
        }

        func end(_ id: String) { busy.remove(id) }
    }

    private func run(_ sequence: [IntegrationAction], extra: [String: String], files: [String: URL],
                     changed: ChangedSettings) async throws -> Outcome {
        var outcome = Outcome()
        // Cookies the device set earlier in this sequence, sent back as `{cookie:<name>}` (a CSRF token).
        var cookies: [String: String] = [:]
        for action in sequence {
            let values = values(extra).merging(cookies.reduce(into: [:]) { $0["cookie:" + $1.key] = $1.value }) { $1 }
            if let request = action.http {
                // A setting changed only for this sequence: what it is now, to put back after.
                if let field = request.restore {
                    // Read as it's written, with the same sign-in and headers, but for a cookie the device sets only now.
                    let headers = request.headers?.filter { $0.key.lowercased() != "content-type" && !$0.value.contains("{cookie:") }
                    let read = Request(port: request.port, path: request.path, headers: headers, auth: request.auth, https: request.https)
                    let now = try await DeviceHTTP.send(read, to: try address, values: values, pins: DeviceTLS.Pins(deviceID: device.id))
                    guard now.ok, let was = DeviceHTTP.value(json: field, xml: nil, in: now),
                          !was.unicodeScalars.contains(where: { !Placeholders.safe.contains($0) }) else {
                        throw Failure(message: "\(device.name) didn't say what \(request.path) is set to, so Lamp left it as it was.")
                    }
                    // Put back only once, as it was first: a sequence tried again finds its own change there.
                    let setting = "\(request.port)\(request.path)"
                    if !changed.restores.contains(where: { "\($0.request.port)\($0.request.path)" == setting }),
                       was != (try? Placeholders.fill(request.body ?? "", values, in: .body)).flatMap({ DeviceHTTP.json(field, in: Data($0.utf8)) }) {
                        changed.restores.append(Restore(request: request, was: was, values: values))
                    }
                }
                var answer = try await DeviceHTTP.send(request, to: try address, values: values, files: files, pins: DeviceTLS.Pins(deviceID: device.id))
                // A device still working on what it was sent says so with 204 until it's done.
                if let poll = request.poll {
                    let until = Date().addingTimeInterval(TimeInterval(min(max(poll, 2), 600)))
                    while answer.status == 204, Date() < until {
                        try await Task.sleep(for: .seconds(2))
                        answer = try await DeviceHTTP.send(request, to: try address, values: values, files: files, pins: DeviceTLS.Pins(deviceID: device.id))
                    }
                    // Still working when the time is up is no answer: the step didn't finish.
                    if answer.status == 204 { throw Failure(message: "\(device.name) was still working on \(request.path) after \(poll) seconds.") }
                }
                cookies.merge(answer.cookies) { $1 }
                if answer.ok { await learnRoot(request, answer) }
                guard answer.ok else {
                    let said = DeviceApps.plain(answer.text)
                    throw Failure(message: "\(device.name) answered \(answer.status) to \(request.path)" + (said.isEmpty ? "." : ": " + said))
                }
                if let expect = request.expect {
                    let value = DeviceHTTP.value(json: expect.json, xml: expect.xml, in: answer) ?? ""
                    let met = expect.equals.map { value.caseInsensitiveCompare($0) == .orderedSame } ?? expect.contains.map { value.localizedCaseInsensitiveContains($0) } ?? true
                    guard met else {
                        throw Failure(message: "\(device.name) said: " + DeviceApps.plain(answer.text))
                    }
                }
                switch request.keep {
                case "picture": outcome.picture = answer.body
                case "log": outcome.log = String(decoding: answer.body.suffix(256 << 10), as: UTF8.self)
                case "key":
                    let file = DeviceFolder.deviceKey(device.id)
                    try answer.body.write(to: file, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                default: outcome.answers.append(String(answer.text.prefix(64 << 10)))
                }
            } else if let probe = action.probe {
                guard try await probed(probe) else { throw Failure(message: "\(device.name) didn't answer (\(probe)).") }
            } else if let stream = action.stream {
                guard let onLog, let running = DeviceStream(address: try address, port: stream.port, onLine: onLog) else {
                    throw Failure(message: "Lamp couldn't read \(device.name)'s log.")
                }
                outcome.streams.append(running)
            } else if action.ssh != nil || action.tool != nil {
                guard let subject = DeviceApprovals.subject(of: action) else { continue }
                if !DeviceApprovals.isApproved(subject, on: device.id) {
                    guard await approve(DeviceCommandApproval(action: action, device: device.name)) else {
                        throw Failure(message: "You didn't allow it, so nothing ran on \(device.name).")
                    }
                    DeviceApprovals.approve(subject, on: device.id)
                }
                if let ssh = action.ssh {
                    outcome.printed.append(try await DeviceSSH.run(ssh, address: try address, deviceID: device.id, values: values))
                } else if let tool = action.tool {
                    outcome.printed.append(try await DeviceTools.run(tool, deviceID: device.id, values: values))
                }
            } else if let signIn = action.vendorSignIn {
                let answer = try await VendorSignIn.run(page: signIn.page, values: values)
                DeviceFields.save(answer, as: "signIn", device: device.id)
            } else if let wait = action.wait {
                try await Task.sleep(for: .seconds(min(max(wait, 1), 30)))
            } else if let bridge = action.bridge {
                throw Failure(message: "The \(bridge) bridge isn't open to integrations yet.")
            }
        }
        return outcome
    }

    private func probed(_ probe: String) async throws -> Bool {
        let parts = probe.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        switch parts[0] {
        case "tcp": return await DeviceProbe.tcp(try address, port: Int(parts[1]) ?? 0)
        case "ssdp": return await DeviceProbe.ssdp(parts[1]).contains { $0.address == device.address }
        case "bonjour": return await DeviceProbe.bonjour(parts[1]).contains { $0.address == device.address }
        default: return false
        }
    }

    /// Whether a step's check passes now, and if not, the first condition that didn't, in words. `failed` is a reason
    /// waiting won't mend (the device's certificate changed, or it rejected the sign-in), which the card shows as a
    /// failure rather than waiting.
    func check(_ step: Integration.Step) async -> (passed: Bool, why: String?, read: String?, failed: Bool) {
        await prepare()
        let values = values()
        var read: String?
        for condition in step.check {
            if let key = condition.field {
                guard values["field:" + key]?.isEmpty == false else { return (false, "Waiting for what you type.", nil, false) }
            } else if condition.signedIn == true {
                guard values["signIn"] != nil else { return (false, "Waiting for you to sign in.", nil, false) }
            } else if let port = condition.tcp {
                guard let address = try? address, await DeviceProbe.tcp(address, port: port) else { return (false, "Waiting for \(device.name)…", nil, false) }
            } else if let request = condition.http {
                let answer: DeviceHTTP.Answer?
                do {
                    answer = try await send(request, try address, values, DeviceTLS.Pins(deviceID: device.id))
                    if let answer, answer.ok { await learnRoot(request, answer) }
                } catch let refusal as DeviceTLS.Refusal {
                    return (false, refusal.localizedDescription, nil, true)
                } catch {
                    answer = nil
                }
                // A device that turns the password away keeps doing so however long Lamp waits: the person has to
                // type it again, so the card says so and stops checking.
                if request.auth != nil, answer?.status == 401 {
                    return (false, "The device rejected the sign-in. Check the user name and password, then try again.", nil, true)
                }
                guard let answer, answer.ok else { return (false, "Waiting for \(device.name)…", nil, false) }
                if condition.json != nil || condition.xml != nil {
                    let value = DeviceHTTP.value(json: condition.json, xml: condition.xml, in: answer)
                    guard let value else { return (false, "\(device.name) doesn't say yet.", nil, false) }
                    if let equals = condition.equals, value.caseInsensitiveCompare(equals) != .orderedSame { return (false, "Waiting for \(device.name)…", nil, false) }
                    if let contains = condition.contains, !value.localizedCaseInsensitiveContains(contains) { return (false, "Waiting for \(device.name)…", nil, false) }
                    read = read ?? value
                }
            }
        }
        return (true, nil, read, false)
    }

    /// A step passed on this device: it's kept, with the step and what the step read.
    func passed(_ step: Integration.Step, read: String?) {
        var keptOne = Integrations.kept(device.id) ?? Integrations.Kept(id: device.id, integration: integration.id, name: device.name, model: device.model,
                                                                        modelID: device.modelID, os: device.os, osVersion: device.osVersion,
                                                                        address: device.address ?? "")
        if !keptOne.passed.contains(step.id) { keptOne.passed.append(step.id) }
        if let read { keptOne.reads[step.id] = read }
        // What the model step read is the device's model from now on, finer than what it said of itself when found.
        if step.model == true, let model = read?.trimmed.nilIfEmpty { keptOne.model = model }
        Integrations.keep(keptOne)
        Integrations.mark(step.id, of: integration.id, model: keptOne.modelID.isEmpty ? Integrations.model(of: keptOne) : keptOne.modelID,
                          version: keptOne.osVersion)
    }
}

/// A command or tool the person is asked about before it first runs on a device: what it is, what it's for in the
/// model's words, and what they accept, in Lamp's.
struct DeviceCommandApproval: Hashable {
    let action: IntegrationAction
    let device: String

    /// The command as shown: its template, with Lamp's values still named.
    var command: String {
        if let ssh = action.ssh { return ssh.command }
        if let tool = action.tool {
            if let name = tool.name, let listed = DeviceTools.listed[name] { return ([listed.program] + listed.arguments).joined(separator: " ") }
            return ([URL(string: tool.download ?? "")?.lastPathComponent ?? "tool"] + (tool.arguments ?? [])).joined(separator: " ")
        }
        return ""
    }

    var explanation: String {
        if let tool = action.tool, let name = tool.name { return DeviceTools.listed[name]?.explanation ?? "" }
        return action.ssh?.explanation ?? action.tool?.explanation ?? ""
    }

    var title: String { action.ssh != nil ? "Run this on \(device)?" : "Run this tool on this Mac?" }

    var accepts: String {
        if action.ssh != nil { return IntegrationWords.accepts(.commandRuns, device: device) }
        if let tool = action.tool, tool.download != nil {
            return "A program from \(URL(string: tool.download ?? "")?.host ?? "the web") runs on this Mac, kept to its own folder and the network, and talks to \(device)."
        }
        return "One of Lamp's own tools runs on this Mac."
    }
}

/// Lamp's words for what an integration can't say itself: what a step costs, and how it's known.
enum IntegrationWords {
    static func accepts(_ acceptance: Integration.Acceptance, device: String) -> String {
        switch acceptance {
        case .account: return "You sign in with an account of yours with the maker, which may ask you to agree to its terms."
        case .softwareRisk: return "It changes \(device)'s software, which can stop it working until it's reset."
        case .warranty: return "The maker may no longer cover \(device) under its warranty."
        case .dataWiped: return "Everything on \(device) is erased."
        case .updatesStop: return "\(device) may stop getting the maker's updates."
        case .protectionsOff: return "Protections that keep \(device) safe are turned off, so other software could get in too."
        case .commandRuns: return "Commands from Lamp run on \(device), which can change or break its software. You approve each one first."
        }
    }

    static func mark(_ known: Integration.Known?) -> (title: String, symbol: String) {
        switch known?.how ?? .read {
        case .lamp: return ("Checked by Lamp", "checkmark.seal")
        // A step done by hand that has passed on a real device: what matters to the person is that it works.
        case .people: return ("Worked before", "person.2")
        case .read: return ("Not tried yet", "questionmark.circle")
        }
    }

    /// The mark's detail, for its help: where it was checked or read.
    static func markDetail(_ known: Integration.Known?) -> String {
        guard let known else { return "Written from what was read, and not yet tried on a device." }
        switch known.how {
        case .read: return "Written from what was read\(known.source.flatMap { URL(string: $0)?.host }.map { " on \($0)" } ?? ""), and not yet tried on a device."
        case .lamp: return "Lamp did it on \([known.model, known.version].compactMap { $0 }.joined(separator: ", ")), and it worked."
        case .people: return "Someone did it by hand on \([known.model, known.version].compactMap { $0 }.joined(separator: ", ")), and it worked."
        }
    }
}
