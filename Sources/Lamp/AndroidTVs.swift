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
        let (resolved, records) = merge(devices, services: services, kept: before)
        if records != before { save(records) }
        return resolved
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
    static func merge(_ devices: [Device], services: [Service], kept: [Record],
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
                out += group
                seen.insert(serial)
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
            // Paired over Wireless debugging once, it's reached that way from then on.
            if transports.contains(.tls) { records[index].transport = .tls }
            let record = records[index]
            let usable = group.indices.filter { record.transport == .legacy || transports[$0] == .tls }
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
            device.address = records[index].address
            device.transport = records[index].transport
            device.kept = true
            out.append(device)
        }
        for record in records where !seen.contains(record.serial) {
            // A TV adb lists only in a state that reads nothing (not allowed, or offline) is shown as that TV when the
            // name adb's search gave it carries its serial, or it's a selector the TV had: that row says what to do on
            // it. Nothing is put on it until it reads its serial again.
            if let index = out.firstIndex(where: { $0.kind == .android && $0.adbState != "device"
                && (serial(inMDNS: $0.id) == record.serial || record.aliases.contains($0.id)) }) {
                let listed = out.remove(at: index)
                var device = away(record)
                device.adbSerial = listed.id
                device.adbState = listed.adbState
                device.connected = true
                out.append(device)
            } else {
                out.append(away(record))
            }
        }
        return (out, records)
    }

    /// A kept TV adb can't see now.
    static func away(_ record: Record) -> Device {
        var device = Device(id: record.id, kind: .android, maker: record.maker, model: record.model, modelID: "", name: record.name,
                            os: "Android", osVersion: record.osVersion, input: ["remote"], features: ["tv"], reach: .network)
        device.adbState = "away"
        device.connected = false
        device.address = record.address
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
    /// after it was first missed), a Fire TV at its last address's 5555. One try per TV a minute; true when one
    /// connected, so the listing is read again.
    static func reconnect(listed: [String], services: [Service], kept: [Record], now: Date = Date()) async -> Bool {
        var targets: [String] = []
        attempts.lock()
        for record in kept {
            let there = listed.contains { record.aliases.contains($0) || serial(inMDNS: $0) == record.serial }
            guard !there else { missingSince[record.id] = nil; continue }
            let since = missingSince[record.id] ?? now
            missingSince[record.id] = since
            guard now.timeIntervalSince(since) >= 5, now.timeIntervalSince(lastTry[record.id] ?? .distantPast) >= 60 else { continue }
            let target: String?
            switch record.transport {
            case .tls:
                target = services.first { $0.transport == .tls && $0.serial == record.serial && DeviceAddress.isPrivate($0.host) }.map { "\($0.host):\($0.port)" }
            case .legacy:
                target = services.first { $0.transport == .legacy && $0.serial == record.serial && DeviceAddress.isPrivate($0.host) }.map { "\($0.host):\($0.port)" }
                    ?? record.address.flatMap { DeviceAddress.isPrivate($0) ? "\($0):5555" : nil }
            }
            guard let target else { continue }
            lastTry[record.id] = now
            targets.append(target)
        }
        attempts.unlock()
        var connected = false
        for target in targets where await Adb.connect(target: target) { connected = true }
        return connected
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
