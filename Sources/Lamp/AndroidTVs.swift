import Foundation

/// The person's Android TVs (Google TV, Android TV, Fire TV), each kept under an id of Lamp's own once this Mac's adb
/// is allowed on it. adb names a TV on the network by a selector that doesn't last: an address and a port that change
/// each time Wireless debugging is turned on, or the name its own search gave the TV's service, and it may list one TV
/// under both at once. So a choice under Try On is this record's id (`project.device`), and every command for the TV
/// goes to the selector adb reaches it by now (`Device.adb`), resolved here from the listing on each look.
///
/// A record is the TV's serial as the TV itself says it (`ro.serialno`), checked, never assumed: a serial that's a
/// placeholder, or that two TVs at different addresses both answer with, makes no record, and those rows stay as adb
/// lists them. The last address is only where to try connecting, since the router may give it to another device.
enum AndroidTVs {
    /// How this Mac is let in: Wireless debugging's paired, encrypted connection, or the old adb port (5555) a Fire TV
    /// offers once ADB debugging is on. A TV paired over the first is never reached over the second.
    enum Transport: String, Codable { case tls, legacy }

    struct Record: Codable, Hashable {
        var id: String
        var serial: String
        var name: String
        var maker: String
        var model: String
        var osVersion: String
        var transport: Transport
        /// The selectors adb has listed it under, newest first.
        var aliases: [String] = []
        var address: String?
    }

    static let idPrefix = "android-tv:"
    static func isRecord(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

    private static var keptURL: URL { Edition.supportFolder.appendingPathComponent("Android/tvs.json") }
    /// Looks run at once (a refresh, Android setup's check, Play): a TV met by two of them is still one record.
    private static let keeping = NSLock()

    static func kept() -> [Record] {
        (try? Data(contentsOf: keptURL)).flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
    }

    private static func save(_ records: [Record]) {
        try? FileManager.default.createDirectory(at: keptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(records).write(to: keptURL, options: .atomic)
    }

    /// Forgets a TV, as the person asks in Settings. adb's own trust in this Mac is the TV's to take back.
    static func forget(_ id: String) {
        keeping.lock()
        defer { keeping.unlock() }
        save(kept().filter { $0.id != id })
    }

    /// The merge of a look (`merge`), with the records it made or changed written back, one look at a time.
    static func resolve(_ devices: [Device], services: [Service]) -> [Device] {
        keeping.lock()
        defer { keeping.unlock() }
        let before = kept()
        let hints = pairings()
        let (resolved, records) = merge(devices, services: services, kept: before, pairedAt: Set(hints.keys))
        if records != before { save(records) }
        // A paired device seen connected over Wireless debugging needs its address's hint no more.
        let seen = Set(resolved.filter { $0.transport == .tls && $0.adbState == "device" }.compactMap(\.address))
        if !seen.isDisjoint(with: hints.keys) { writePairings(hints.filter { !seen.contains($0.key) }) }
        return resolved
    }

    // MARK: Paired over Wireless debugging

    /// A pairing over Wireless debugging says the device paired is to be reached over its encrypted connection, never
    /// the old port, from the moment it worked, whether or not the window was still open to see the connection. Two
    /// things are kept, apart. The device's own record is marked so for good, but only by its identity: the serial
    /// read from the device answering at the pairing's address as it paired (`promoted`), or later the encrypted
    /// connection seen (`merge`). The address is kept too, for a day at most, by when (`pairedAt`): while it's recent,
    /// nothing at that address is reached over the old port. That's a hint, never a mark on a record, since the router
    /// may give the address to another device; it ends early once the paired device is seen connected that way.
    private static var pairedURL: URL { Edition.supportFolder.appendingPathComponent("Android/paired.json") }
    static let pairingLasts: TimeInterval = 24 * 3600

    static func paired(at host: String, serial: String?, now: Date = Date()) {
        keeping.lock()
        defer { keeping.unlock() }
        let records = kept(), marked = promoted(records, serial: serial)
        if marked != records { save(marked) }
        var all = pairings(now: now)
        all[host] = now.timeIntervalSince1970
        writePairings(all)
    }

    /// The records of the device with that serial, marked to be reached over Wireless debugging; no other record.
    static func promoted(_ records: [Record], serial: String?) -> [Record] {
        guard let serial, isUsable(serial) else { return records }
        return records.map { record in
            var record = record
            if record.serial == serial { record.transport = .tls }
            return record
        }
    }

    private static func writePairings(_ all: [String: Double]) {
        try? FileManager.default.createDirectory(at: pairedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: pairedURL, options: .atomic)
    }

    private static func pairings(now: Date = Date()) -> [String: Double] {
        let all = (try? Data(contentsOf: pairedURL)).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
        return all.filter { now.timeIntervalSince1970 - $0.value < pairingLasts }
    }

    static func pairedHosts(now: Date = Date()) -> Set<String> { Set(pairings(now: now).keys) }

    /// Whether the device at an address is to be reached over Wireless debugging only: one paired there lately (the
    /// day-long hint, for a device not yet known by its serial), or a kept TV marked so that's at that address now, known
    /// there by its serial (a live record's address is where it read its serial, or where adb's search name carrying it
    /// points). A kept TV that's away puts no rule on the address it last had.
    static func requiresTLS(_ host: String, among devices: [Device], pairedAt: Set<String>) -> Bool {
        pairedAt.contains(host) || devices.contains { isRecord($0.id) && $0.transport == .tls && $0.connected && $0.address == host }
    }

    // MARK: What adb says

    /// One line of `adb mdns services`: "adb-SERIAL-Ab12Cd  _adb-tls-connect._tcp  192.168.1.20:37123".
    struct Service: Hashable {
        let name: String
        let type: String
        let host: String
        let port: Int
        var transport: Transport? {
            type.hasPrefix("_adb-tls-connect") ? .tls : type.hasPrefix("_adb._tcp") ? .legacy : nil
        }
        var isPairing: Bool { type.hasPrefix("_adb-tls-pairing") }
        /// The serial adb's search names it by: "adb-<serial>-<suffix>" for Wireless debugging, "adb-<serial>" for the
        /// old port. Pairing's name is the device's own random one and says nothing.
        var serial: String? { AndroidTVs.serial(instance: name, transport: transport) }
    }

    static func services(_ output: String) -> [Service] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 3, let colon = fields[2].lastIndex(of: ":"), let port = Int(fields[2][fields[2].index(after: colon)...]) else { return nil }
            return Service(name: fields[0], type: fields[1], host: String(fields[2][..<colon]), port: port)
        }
    }

    /// A selector that's the name adb's search found a service by ("adb-SERIAL-Ab12Cd._adb-tls-connect._tcp").
    static func isMDNS(_ selector: String) -> Bool { selector.hasPrefix("adb-") && selector.contains("._adb") && selector.hasSuffix("._tcp") }

    /// The serial in an mDNS selector, nil for an address or anything else.
    static func serial(inMDNS selector: String) -> String? {
        guard isMDNS(selector), let dot = selector.range(of: "._adb") else { return nil }
        let type = String(selector[dot.lowerBound...].dropFirst())
        return serial(instance: String(selector[..<dot.lowerBound]), transport: Service(name: "", type: type, host: "", port: 0).transport)
    }

    private static func serial(instance: String, transport: Transport?) -> String? {
        guard instance.hasPrefix("adb-"), let transport else { return nil }
        let rest = instance.dropFirst(4)
        guard transport == .tls else { return rest.isEmpty ? nil : String(rest) }
        guard let dash = rest.lastIndex(of: "-") else { return nil }
        let serial = rest[..<dash]
        return serial.isEmpty ? nil : String(serial)
    }

    /// A serial that names one device. Some builds answer with a placeholder, which many devices share.
    static func isUsable(_ serial: String?) -> Bool {
        guard let serial = serial?.trimmingCharacters(in: .whitespaces), serial.count >= 6 else { return false }
        if ["unknown", "0123456789abcdef", "0123456789", "null", "none", "serial"].contains(serial.lowercased()) { return false }
        return Set(serial).count > 1
    }

    /// The address a selector reaches: an "address:port" says it; an mDNS name is looked up in adb's search.
    static func address(of selector: String, services: [Service]) -> String? {
        if isMDNS(selector), let dot = selector.range(of: "._adb") {
            let name = String(selector[..<dot.lowerBound]), type = String(selector[dot.lowerBound...].dropFirst())
            return services.first { $0.name == name && type.hasPrefix($0.type) }?.host
        }
        guard let colon = selector.lastIndex(of: ":"), Int(selector[selector.index(after: colon)...]) != nil else { return nil }
        return String(selector[..<colon])
    }

    /// Which way a selector reaches its device: by its mDNS service's type, or for an "address:port" by what adb's
    /// search says is listening there, else by the port (5555 is the old one).
    static func transport(of selector: String, services: [Service]) -> Transport? {
        if isMDNS(selector), let dot = selector.range(of: "._adb") {
            return Service(name: "", type: String(selector[dot.lowerBound...].dropFirst()), host: "", port: 0).transport
        }
        guard let host = address(of: selector, services: services), let port = Int(selector.split(separator: ":").last ?? "") else { return nil }
        if let listed = services.first(where: { $0.host == host && $0.port == port })?.transport { return listed }
        return port == 5555 ? .legacy : .tls
    }

    // MARK: One row per TV

    /// adb's devices with Android TVs folded into their records: a TV listed under two selectors is one row when both
    /// reach the same address and read the same serial; one adb can't see now is still listed, as away, so a choice
    /// of it isn't lost. Anything that isn't an authorized TV on the network, and every ambiguous one, stays as adb
    /// listed it. `newID` names a record made for a TV met for the first time.
    static func merge(_ devices: [Device], services: [Service], kept: [Record], pairedAt: Set<String> = [],
                      newID: () -> String = { idPrefix + UUID().uuidString.lowercased() }) -> (devices: [Device], kept: [Record]) {
        var records = kept
        var out: [Device] = []
        var seen: Set<String> = []
        func isTV(_ device: Device) -> Bool {
            device.kind == .android && device.reach == .network && device.features.contains("tv") && device.adbState == "device" && isUsable(device.serialNumber)
        }
        // Every device on the network gets its address, an mDNS name's from adb's search, so a window waiting for one
        // at an address sees it whichever way adb connected it.
        out += devices.filter { !isTV($0) }.map { device in
            var device = device
            if device.reach == .network, device.address == nil { device.address = address(of: device.id, services: services) }
            return device
        }
        // Grouped in the order adb listed them, so the same listing always gives the same rows.
        var groups: [(serial: String, devices: [Device])] = []
        for device in devices where isTV(device) {
            let serial = device.serialNumber ?? ""
            if let index = groups.firstIndex(where: { $0.serial == serial }) { groups[index].devices.append(device) } else { groups.append((serial, [device])) }
        }
        for (serial, group) in groups {
            let addresses = group.map { address(of: $0.id, services: services) }
            let oneTV = group.count == 1 || (addresses.allSatisfy { $0 != nil } && Set(addresses).count == 1)
            let matching = records.indices.filter { records[$0].serial == serial }
            guard oneTV, matching.count <= 1 else {
                // Left as adb listed them. A record with this serial is shown as unsure, not as one of them.
                out += group
                seen.insert(serial)
                for index in matching {
                    var device = away(records[index])
                    device.adbState = "unsure"
                    out.append(device)
                }
                continue
            }
            let transports = group.map { transport(of: $0.id, services: services) }
            let index: Int
            if let found = matching.first {
                index = found
            } else {
                let first = group[0]
                records.append(Record(id: newID(), serial: serial, name: first.name, maker: first.maker, model: first.model,
                                      osVersion: first.osVersion, transport: transports.contains(.tls) ? .tls : .legacy))
                index = records.count - 1
            }
            seen.insert(serial)
            // Seen connected over Wireless debugging once, it's reached that way from then on.
            if transports.contains(.tls) { records[index].transport = .tls }
            let record = records[index]
            // A recent pairing at an address keeps the old port there out of use, whichever record it is, for as long
            // as the hint lasts; the record itself isn't changed by it.
            let usable = group.indices.filter {
                transports[$0] == .tls || (record.transport == .legacy && addresses[$0].map(pairedAt.contains) != true)
            }
            // adb's own name for the TV first: it's the selector adb keeps reconnecting by itself.
            let pick = usable.sorted { (isMDNS(group[$0].id) ? 0 : 1, group[$0].id) < (isMDNS(group[$1].id) ? 0 : 1, group[$1].id) }.first
            records[index].aliases = Array((group.map(\.id) + record.aliases).uniqued().prefix(8))
            records[index].address = addresses.compactMap { $0 }.first ?? record.address
            guard let pick else {
                out.append(away(records[index]))
                continue
            }
            let live = group[pick]
            records[index].name = live.name
            records[index].model = live.model
            records[index].maker = live.maker
            records[index].osVersion = live.osVersion
            var device = live
            device.id = record.id
            device.adbSerial = live.id
            device.aliases = group.map(\.id)
            // Where this look saw it, or nothing: the record's last address is only where reconnecting tries.
            device.address = addresses.compactMap { $0 }.first
            device.transport = records[index].transport
            device.kept = true
            out.append(device)
        }
        for record in records where !seen.contains(record.serial) {
            // A TV adb lists only in a state that reads nothing (not allowed, or offline) is shown as that TV when the
            // name adb's search gave it carries its serial: that row says what to do on it. Nothing is put on it until
            // it reads its serial again.
            if let index = out.firstIndex(where: { $0.kind == .android && $0.adbState != "device" && serial(inMDNS: $0.id) == record.serial }) {
                let listed = out.remove(at: index)
                var device = away(record)
                device.adbSerial = listed.id
                device.adbState = listed.adbState
                device.connected = true
                // Where it answers now, from that row: the record's last address says nothing of what's there.
                device.address = listed.address ?? address(of: listed.id, services: services)
                out.append(device)
            } else {
                out.append(away(record))
            }
        }
        return (out, records)
    }

    /// A kept TV adb can't see now. It has no address: the last one it had is only where reconnecting tries
    /// (`Record.address`), and another device may have it now, so nothing that goes by a device's address (the window's
    /// rules, the network list's names, Try On's found TVs) may take it for this TV.
    static func away(_ record: Record) -> Device {
        var device = Device(id: record.id, kind: .android, maker: record.maker, model: record.model, modelID: "", name: record.name,
                            os: "Android", osVersion: record.osVersion, input: ["remote"], features: ["tv"], reach: .network)
        device.adbState = "away"
        device.connected = false
        device.serialNumber = record.serial
        device.transport = record.transport
        device.aliases = record.aliases
        device.kept = true
        return device
    }

    /// Whether an old choice (a selector adb had for a TV) can become the record of the TV now answering under it
    /// without asking: only the name adb's search gives a TV, carrying a serial that's the one the TV reads.
    static func adopts(_ chosen: String, as device: Device) -> Bool {
        guard isRecord(device.id), device.aliases.contains(chosen), let serial = serial(inMDNS: chosen) else { return false }
        return isUsable(serial) && serial == device.serialNumber
    }

    /// What a choice under Try On names, and whether it can be used as it is.
    enum Choice: Equatable {
        case use(Device)
        /// An old choice that's this TV's record now: use it, and save the record's id in its place.
        case adopt(Device)
        /// A device answers where the choice points, but nothing says it's the one chosen: the person chooses again.
        case confirm(Device)
        case missing
    }

    /// A record's id is the TV's. A cable's serial and an emulator's are theirs, as adb lists them. A network
    /// selector (an address and port, or adb's mDNS name) chosen before is a place, not a device: adb's mDNS name carrying
    /// the serial the TV there reads is adopted as that TV's record; any other TV answering there, recorded or not, is
    /// used only once the person chose that selector under Try On in this run of Lamp (`confirmed`). A phone over Wi‑Fi
    /// that said it isn't a TV is used as it was chosen: Lamp keeps no records of phones.
    static func choice(_ chosen: String, among devices: [Device], confirmed: Set<String>) -> Choice {
        if isRecord(chosen) { return devices.first { $0.id == chosen }.map { .use($0) } ?? .missing }
        let exact = devices.first { $0.id == chosen }
        guard chosen.contains(":") || isMDNS(chosen) else { return exact.map { .use($0) } ?? .missing }
        if let tv = devices.first(where: { adopts(chosen, as: $0) }) { return .adopt(tv) }
        guard let answering = exact ?? devices.first(where: { isRecord($0.id) && $0.aliases.contains(chosen) }) else { return .missing }
        // Only a device that said it isn't a TV is a phone: one whose description couldn't be read may be a TV.
        if answering.describedItself, !answering.features.contains("tv"), !isRecord(answering.id), answering.adbState == "device" { return .use(answering) }
        return confirmed.contains(chosen) ? .use(answering) : .confirm(answering)
    }

    /// Where Stop closes the app when Lamp isn't watching it open: the selector the choice can be used at now, or nil.
    /// An old address that's unconfirmed is never used: another device may have it.
    static func stopTarget(_ chosen: String, among devices: [Device], confirmed: Set<String>) -> String? {
        switch choice(chosen, among: devices, confirmed: confirmed) {
        case .use(let device), .adopt(let device): return device.adbState == "device" ? device.adb : nil
        case .confirm, .missing: return nil
        }
    }

    /// Whether a selector reaches its device over Wireless debugging's connection.
    static func isTLS(_ selector: String, services: [Service]) -> Bool { transport(of: selector, services: services) == .tls }

    // MARK: Found before its debugging is on

    /// TVs the look on the network found that are Google TVs or Android TVs: a host offering both the TV's remote service
    /// and Cast at the same address, named by Cast's own name for it. Shown so the person can set one up; found isn't
    /// theirs (a neighbor's answers too), so nothing connects to it and nothing is kept until this Mac is allowed on it.
    static func found(in hosts: [NetworkHost]) -> [AndroidWiFi.Found] {
        hosts.filter { $0.types.isSuperset(of: ["_androidtvremote2._tcp", "_googlecast._tcp"]) && !$0.isThisMac }.map { host in
            let name = host.services.first { $0.type == "_googlecast._tcp" }?.txt["fn"] ?? host.names.first
            return AndroidWiFi.Found(host: host.address, name: name)
        }
    }

    // MARK: Connecting again

    private static let attempts = NSLock()
    nonisolated(unsafe) private static var missingSince: [String: Date] = [:]
    nonisolated(unsafe) private static var lastTry: [String: Date] = [:]

    /// Connects kept TVs adb doesn't list, where Lamp knows where they listen: one paired over Wireless debugging at
    /// the port its service offers now (adb usually connects those itself, so only one still missing a few seconds
    /// after it was first missed), a Fire TV where its service says, else at its last address's 5555. One try per TV
    /// a minute; true when one connected, so the listing is read again.
    static func reconnect(listed: [String], services: [Service], kept: [Record], now: Date = Date()) async -> Bool {
        var targets: [String] = []
        let pairedAt = pairedHosts(now: now)
        attempts.lock()
        // While the person is connecting a device themselves, nothing else connects anything.
        if settingUp { attempts.unlock(); return false }
        for record in kept {
            let there = listed.contains { record.aliases.contains($0) || serial(inMDNS: $0) == record.serial }
            guard !there else { missingSince[record.id] = nil; continue }
            let since = missingSince[record.id] ?? now
            missingSince[record.id] = since
            // adb connects a TV paired over Wireless debugging itself once its search sees it, so that one is given a
            // moment first; nothing connects a Fire TV's old port but Lamp.
            guard record.transport == .legacy || now.timeIntervalSince(since) >= 5,
                  now.timeIntervalSince(lastTry[record.id] ?? .distantPast) >= 60 else { continue }
            let target: String?
            switch record.transport {
            case .tls:
                target = services.first { $0.transport == .tls && $0.serial == record.serial && DeviceAddress.isPrivate($0.host) }.map { "\($0.host):\($0.port)" }
            case .legacy where pairedAt.contains(record.address ?? ""):
                target = nil
            case .legacy:
                target = services.first { $0.transport == .legacy && $0.serial == record.serial && DeviceAddress.isPrivate($0.host) }.map { "\($0.host):\($0.port)" }
                    ?? record.address.flatMap { DeviceAddress.isPrivate($0) ? "\($0):5555" : nil }
            }
            guard let target, !inFlight.contains(host(of: target)) else { continue }
            lastTry[record.id] = now
            inFlight.insert(host(of: target))
            targets.append(target)
        }
        attempts.unlock()
        var connected = false
        for target in targets {
            if await Adb.connect(target: target) { connected = true }
            finished(target)
        }
        return connected
    }

    /// Set while the Wi‑Fi window is open: the person's own pairing and connecting go one at a time, and Lamp's
    /// reconnecting waits for them.
    nonisolated(unsafe) static var settingUp = false {
        willSet { attempts.lock() }
        didSet { attempts.unlock() }
    }
    nonisolated(unsafe) private static var inFlight: Set<String> = []

    private static func host(of target: String) -> String { target.split(separator: ":").dropLast().joined(separator: ":") }

    private static func finished(_ target: String) {
        attempts.lock()
        inFlight.remove(host(of: target))
        attempts.unlock()
    }

    /// Runs one of the window's own requests to an address once no reconnect of Lamp's is in flight to it, and keeps
    /// any from starting meanwhile.
    static func exclusively<T>(_ target: String, _ work: () async -> T?) async -> T? {
        let host = host(of: target)
        while true {
            attempts.lock()
            if !inFlight.contains(host) { inFlight.insert(host); attempts.unlock(); break }
            attempts.unlock()
            try? await Task.sleep(for: .milliseconds(200))
        }
        defer { finished(target) }
        return await work()
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
