import Darwin
import Foundation

/// Everything on the person's home network, one record per address, for when the person is looking for devices (Your
/// Devices, Add a New Device, `network_devices`): never at launch or on a timer. SSDP and the integrations find what
/// Lamp can work with; this finds the rest, so the list can say what else is there and the agent can work out what
/// each one is. It only reads: one small datagram to each address of this Mac's own subnet, so the Mac's neighbor
/// table fills (a phone that ignores everything else still answers the Mac's ARP), that table, and every Bonjour
/// service on the network, all of it lamp's command line's (`network` and `neighbours` in cli/calls.mjs, cli/network.mjs);
/// and here, the maker of each hardware address from the IEEE's registry (`Vendors`). Nothing is kept on disk: the
/// names a network holds are often people's ("…'s iPhone"), so they're shown on this Mac and told to the agent the
/// person uses, and go nowhere else.
struct NetworkHost: Hashable, Identifiable {
    var id: String { address }
    let address: String
    /// Its hardware address, "38:b4:d3:31:25:e0", from this Mac's neighbor table.
    var mac: String?
    /// The maker of its network hardware, from the address's prefix ("Espressif", "BSH Hausgeräte").
    var vendor: String?
    /// A hardware address the device made up (a phone's, tablet's or computer's private Wi‑Fi address): it names no
    /// maker and changes, so such a device is counted, not named.
    var randomised = false
    var isThisMac = false
    var isGateway = false
    var services: [BonjourService] = []
    /// What it said to Lamp's SSDP search, and its UPnP description when it has one.
    var ssdpServers: [String] = []
    var upnp: UPnP?

    struct UPnP: Hashable {
        var name: String
        var maker: String
        var model: String
    }

    /// The names it gives itself on the network: its services' and its Bonjour host's ("Living Room", "Kitchen-Speaker").
    /// Often a person's, so only for this Mac's screen and the agent.
    var names: [String] {
        var names: [String] = []
        for name in services.map(\.name) + services.map(\.hostLabel) + [upnp?.name].compactMap({ $0 })
        where !name.isEmpty && !Self.isID(name) && !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.append(name)
        }
        return names
    }

    /// A name that is an identifier rather than a name: a pairing service's hardware address and link-local address, or
    /// a UUID.
    static func isID(_ name: String) -> Bool {
        name.contains("@fe80") || name.range(of: "^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$", options: .regularExpression) != nil
    }

    /// The model it says it is, in a service's record ("Chromecast", "AppleTV14,1") or its UPnP description.
    var model: String? {
        if let upnp, !upnp.model.isEmpty { return upnp.model }
        for key in ["md", "model", "am", "ty", "usb_MDL", "product"] {
            if let value = services.lazy.compactMap({ $0.txt[key] }).first(where: { !$0.isEmpty }) {
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            }
        }
        return nil
    }

    /// The maker as the device says it, else as its hardware's address says it.
    var maker: String? { upnp?.maker.nilIfEmpty ?? services.lazy.compactMap { $0.txt["usb_MFG"] ?? $0.txt["manufacturer"] }.first ?? vendor }

    var types: Set<String> { Set(services.map(\.type)) }

    /// What kind of Apple device it is, by the model its records give ("Mac16,1", "AppleTV14,1"): Apple's own devices
    /// often have private addresses, so their hardware says nothing.
    var apple: String? {
        guard let model = services.lazy.compactMap({ $0.txt["model"] ?? $0.txt["am"] }).first, model.contains(",") else {
            return !types.isDisjoint(with: ["_companion-link._tcp", "_apple-mobdev2._tcp", "_remotepairing._tcp"]) || vendor == "Apple" ? "Apple device" : nil
        }
        for (prefix, kind) in [("AppleTV", "Apple TV"), ("AudioAccessory", "HomePod"), ("iPhone", "iPhone"), ("iPad", "iPad"),
                               ("Watch", "Apple Watch"), ("iMac", "Mac"), ("Mac", "Mac")] where model.hasPrefix(prefix) {
            return kind
        }
        return "Apple device"
    }
}

/// One Bonjour service on the network: its type, the name it goes by, its host and what its record says that tells
/// what the device is (model keys, and a Cast device's own name, which is like the host's names; nothing that
/// identifies the device or the person further).
struct BonjourService: Hashable {
    let type: String
    /// The name it goes by. AirPlay's speaker service puts the device's hardware id before it ("F21FB5024962@Kitchen"),
    /// which is taken off.
    let name: String
    let host: String
    var txt: [String: String] = [:]

    init(type: String, name: String, host: String, txt: [String: String] = [:]) {
        self.type = type
        self.name = name.replacingOccurrences(of: "^[0-9A-Fa-f]{12}@", with: "", options: .regularExpression)
        self.host = host
        self.txt = txt
    }

    /// The host's name without ".local.": "Kitchen-Speaker".
    var hostLabel: String { host.components(separatedBy: ".").first ?? host }

    static let modelKeys: Set<String> = ["md", "model", "am", "ty", "usb_MFG", "usb_MDL", "product", "manufacturer", "fn"]
}

enum HomeNetwork {
    /// What a look on the network found besides SSDP: the hosts of this Mac's subnet with their hardware addresses, and
    /// every Bonjour service. `swept` says how much of the subnet was swept, for the agent: on a network bigger than a
    /// /24 only the 256 addresses around this Mac's are.
    struct Look {
        var hosts: [NetworkHost] = []
        var swept: Subnet?
    }

    /// Sweeps this Mac's subnet and browses Bonjour meanwhile, through lamp's command line, then reads the neighbor
    /// table (`Neighbours`, here). Sends nothing anywhere else. One that fails finds nothing, and says why in Lamp's log.
    static func look() async -> Look {
        let done: [String: Any]
        do { done = try await LampCLI.ask("network", [:]) } catch {
            NSLog("Lamp couldn't look at the network: \(error.localizedDescription)")
            return Look()
        }
        let subnet = (done["swept"] as? [String: Any]).flatMap(Subnet.init(said:))
        let table = Neighbours.table(), mine = TVs.macAddresses()
        var hosts: [String: NetworkHost] = [:]
        for (address, mac) in table where subnet?.contains(address) ?? DeviceAddress.isPrivate(address) || mine.contains(address) {
            var host = NetworkHost(address: address, mac: mac)
            host.randomised = Vendors.isRandomised(mac)
            host.vendor = host.randomised ? nil : Vendors.maker(of: mac)
            hosts[address] = host
        }
        // The command line's hosts, each with its Bonjour services, are all within the subnet.
        for said in done["hosts"] as? [[String: Any]] ?? [] {
            guard let address = said["address"] as? String else { continue }
            var host = hosts[address] ?? NetworkHost(address: address)
            host.isThisMac = said["isThisMac"] as? Bool ?? false
            host.isGateway = said["isGateway"] as? Bool ?? false
            host.services = (said["services"] as? [[String: Any]] ?? []).compactMap { service in
                guard let type = service["type"] as? String, let name = service["name"] as? String, let host = service["host"] as? String else { return nil }
                return BonjourService(type: type, name: name, host: host, txt: service["txt"] as? [String: String] ?? [:])
            }
            hosts[address] = host
        }
        let gateway = done["gateway"] as? String
        for address in hosts.keys {
            hosts[address]?.isThisMac = mine.contains(address)
            hosts[address]?.isGateway = address == gateway
        }
        return Look(hosts: hosts.values.sorted { order($0.address) < order($1.address) }, swept: subnet)
    }

    /// The network as it is now, read with nothing sent: this Mac's subnet and its gateway, through lamp's command line,
    /// and the neighbor table, here.
    struct Now {
        var table: [String: String] = [:]
        var gateway: String?
        var subnet: Subnet?
    }

    static func now() async -> Now {
        let table = Neighbours.table()
        guard let done = try? await LampCLI.ask("neighbours", [:]) else { return Now(table: table) }
        return Now(table: table, gateway: done["gateway"] as? String,
                   subnet: (done["subnet"] as? [String: Any]).flatMap(Subnet.init(said:)))
    }

    /// What the SSDP scan and the UPnP descriptions already read said of each host, added to its record.
    static func merge(_ hosts: [NetworkHost], scan: Integrations.Scan, devices: [Device]) -> [NetworkHost] {
        var hosts = Dictionary(uniqueKeysWithValues: hosts.map { ($0.address, $0) })
        for answer in scan.answers where DeviceAddress.isPrivate(answer.address) || hosts[answer.address] != nil {
            var host = hosts[answer.address] ?? NetworkHost(address: answer.address)
            if !answer.server.isEmpty, !host.ssdpServers.contains(answer.server) { host.ssdpServers.append(answer.server) }
            hosts[answer.address] = host
        }
        for device in devices where device.reach == .network {
            guard let address = device.address, var host = hosts[address] else { continue }
            if host.upnp == nil, !device.maker.isEmpty || !device.model.isEmpty {
                host.upnp = NetworkHost.UPnP(name: device.name, maker: device.maker, model: device.model)
            }
            hosts[address] = host
        }
        return hosts.values.sorted { order($0.address) < order($1.address) }
    }

    /// Whether this Mac is still on the network a whole look swept: the same subnet, and the same router at its gateway.
    /// The hosts of the last whole look still at their address now, by the neighbor table (read, nothing sent): one
    /// gone, or another device at its address, is left out.
    static func stillHere(_ hosts: [NetworkHost], now: Now) -> [NetworkHost] {
        hosts.filter { host in host.mac.map { now.table[host.address] == $0 } ?? false }
    }

    static func sameNetwork(as swept: Subnet?, router: String?, now: Now) -> Bool {
        guard let swept, let subnet = now.subnet, subnet.network == swept.network, subnet.prefix == swept.prefix else { return false }
        // Without the router's hardware address the network can't be told from another on the same subnet.
        guard let router else { return false }
        return now.gateway.flatMap { now.table[$0] } == router
    }

    private static func order(_ address: String) -> UInt32 { Subnet.value(address) ?? .max }

    // MARK: What Lamp can do with each

    /// Where a device or host goes in the list: what Lamp makes apps for or controls, what Lamp could learn to work
    /// with, and the rest (the router, printers, appliances, phones), folded away.
    enum Place: Hashable { case works, couldLearn, other }

    /// The services that say a host is plumbing: printing and scanning, and the ones computers and phones offer each
    /// other. Anything else a host offers is something Lamp could learn to reach.
    static let plumbing: Set<String> = [
        "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp", "_uscan._tcp", "_uscans._tcp", "_scanner._tcp",
        "_canon-chmp._tcp", "_privet._tcp", "_companion-link._tcp", "_apple-mobdev2._tcp", "_remotepairing._tcp",
        "_rdlink._tcp", "_asquic._udp", "_device-info._tcp", "_sleep-proxy._udp", "_smb._tcp", "_afpovertcp._tcp",
        "_ssh._tcp", "_sftp-ssh._tcp", "_adisk._tcp", "_airdrop._tcp", "_adb._tcp", "_adb-tls-connect._tcp",
        "_adb-tls-pairing._tcp", "_lampwish._tcp",
    ]

    /// Devices Lamp controls from an app without an integration: what's said of them in the list and to the agent.
    static let controlled: [(maker: String, type: String, words: String)] = [
        ("Sonos", "_sonos._tcp", "Lamp's Universal Remote starter controls it (UPnP on port 1400; the device-control skill)."),
    ]

    static func controls(_ device: Device, host: NetworkHost?) -> String? {
        controlled.first { device.maker.localizedCaseInsensitiveContains($0.maker) || host?.types.contains($0.type) == true }?.words
    }

    /// A host nothing of Lamp's found as a device: whether it says enough of itself to be learned, or is plumbing.
    static func couldLearn(_ host: NetworkHost) -> Bool {
        guard !host.isGateway, !host.isThisMac else { return false }
        let types = host.types
        // An Apple device's AirPlay says what it plays, not what it is: a Mac offers it too. Apple's devices can't be
        // reached by an app the way others can (their pairing is Apple's own), so they're shown, not offered.
        if host.apple != nil { return false }
        if !types.isDisjoint(with: ["_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_uscan._tcp"]) { return false }
        return host.upnp != nil || !types.subtracting(plumbing).isEmpty
    }

    /// A short word for a host that isn't a device of Lamp's, for the folded list: the router, this Mac, a printer,
    /// else its model or maker. A private hardware address with nothing else said is counted, never named.
    static func label(_ host: NetworkHost) -> String {
        if host.isGateway { return "Router" + (host.maker.map { " · " + $0 } ?? "") }
        if host.isThisMac { return "This Mac" }
        let types = host.types
        if !types.isDisjoint(with: ["_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp"]) {
            return "Printer" + (host.maker.map { " · " + $0 } ?? "")
        }
        if let apple = host.apple { return apple }
        if let model = host.model, let maker = host.maker { return model.localizedCaseInsensitiveContains(maker) ? model : "\(maker) \(model)" }
        if let maker = host.maker { return maker }
        return host.randomised ? "Private address" : "Unknown maker"
    }

    /// A device for Set Up… on a host Lamp could learn that SSDP didn't describe: named by what it is, never by the
    /// names it goes by on the network, since a setup conversation's name is written into its folder.
    static func device(for host: NetworkHost) -> Device {
        let maker = host.maker ?? ""
        let model = host.model ?? ""
        let name = [maker, model].filter { !$0.isEmpty }.joined(separator: " ").nilIfEmpty ?? "Device at \(host.address)"
        // The hardware address goes in the id too: the same address may be another device's later (a new lease, another
        // network), and Set Up… reopens a conversation by its id.
        var device = Device(id: "found:\(host.address)" + (host.mac.map { "#" + $0 } ?? ""), kind: .other, maker: maker, model: model.isEmpty ? maker : model,
                            modelID: "", name: name, os: "", osVersion: "", reach: .network)
        device.address = host.address
        return device
    }

    /// The list as Your Devices shows it: the person's devices, set up with Lamp (away or part-way through setup too), in
    /// the order Lamp found them; then what Lamp only found on the network that it makes apps for or controls, which may
    /// be a neighbor's; then the devices Lamp could learn; then every other host on the network, and a count of those
    /// with private addresses that say nothing else, since nothing tells one such phone from another.
    struct List {
        var works: [Device] = []
        /// Found, not set up, and of a kind Lamp works with: a TV, a device an integration knows, one an app can control.
        var possible: [Device] = []
        var couldLearn: [Device] = []
        var others: [NetworkHost] = []
        var unnamed = 0
        /// What controls a device Lamp has no integration for, by its id.
        var controls: [String: String] = [:]

        init(devices: [Device], hosts: [NetworkHost]) {
            let byAddress = Dictionary(hosts.map { ($0.address, $0) }, uniquingKeysWith: { first, _ in first })
            for device in devices {
                if device.kind == .other, device.integration == nil {
                    if let words = HomeNetwork.controls(device, host: device.address.flatMap { byAddress[$0] }) {
                        controls[device.id] = words
                        possible.append(device)
                    } else {
                        couldLearn.append(device)
                    }
                } else if device.isSetUp {
                    works.append(device)
                } else {
                    possible.append(device)
                }
            }
            let listed = Set(devices.compactMap(\.address))
            for host in hosts where !listed.contains(host.address) && !host.isThisMac {
                if host.randomised, host.services.isEmpty, host.upnp == nil { unnamed += 1 } else { others.append(host) }
            }
            // The router first, then by what each is.
            others.sort { ($0.isGateway ? 0 : 1, HomeNetwork.label($0)) < ($1.isGateway ? 0 : 1, HomeNetwork.label($1)) }
        }
    }

    // MARK: Told to the agent

    /// A host's facts in one line, for the agent to work out what it is: address, hardware maker, the gateway or this
    /// Mac, its services and the names they go by, what its records say of its model, and its SSDP answer.
    static func facts(_ host: NetworkHost) -> String {
        var parts: [String] = []
        if host.isGateway { parts.append("the network's gateway") }
        if host.isThisMac { parts.append("this Mac") }
        if host.randomised { parts.append("a private (randomised) hardware address, so no maker") }
        else if let vendor = host.vendor { parts.append("hardware by \(vendor)") }
        else if host.mac != nil { parts.append("hardware maker not in the registry") }
        if !host.services.isEmpty {
            let types = Array(Set(host.services.map(\.type))).sorted().joined(separator: ", ")
            parts.append("Bonjour: \(types)")
        }
        let names = host.names
        if !names.isEmpty { parts.append("goes by " + names.prefix(4).map { "\"\(one($0))\"" }.joined(separator: ", ")) }
        var record: [String] = []
        for service in host.services {
            for (key, value) in service.txt.sorted(by: { $0.key < $1.key }) where !record.contains("\(key)=\(value)") { record.append("\(key)=\(value)") }
        }
        if !record.isEmpty { parts.append("its records say " + record.prefix(6).map(one).joined(separator: ", ")) }
        if let upnp = host.upnp { parts.append("UPnP: " + [upnp.maker, upnp.model].filter { !$0.isEmpty }.map(one).joined(separator: " ")) }
        if !host.ssdpServers.isEmpty { parts.append("SSDP server " + one(host.ssdpServers.prefix(2).joined(separator: ", ")).prefix(120)) }
        if parts.isEmpty { parts.append("answered the Mac's ARP and nothing else") }
        return "\(host.address): " + parts.joined(separator: "; ")
    }

    private static func one(_ text: String) -> String {
        String(text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces).prefix(80))
    }
}

// MARK: - The subnet and the sweep

/// This Mac's own subnet on the network its default route goes through, as far as Lamp sweeps it: the whole of a /24
/// or smaller, and the /24 around this Mac's address on a bigger one (a /16 is 65,000 addresses: too many to knock on).
struct Subnet: Hashable {
    let network: UInt32
    let prefix: Int
    /// The prefix the network really has, when it's bigger than what's swept.
    let actualPrefix: Int
    let mine: UInt32

    static let widest = 24

    var size: UInt32 { 1 << UInt32(32 - prefix) }

    /// The addresses to sweep: all but the network's own, its broadcast and this Mac's.
    var addresses: [UInt32] {
        guard size > 2 else { return [] }
        return (1..<(size - 1)).map { network + $0 }.filter { $0 != mine }
    }

    func contains(_ address: String) -> Bool {
        guard let value = Subnet.value(address) else { return false }
        return value & mask == network
    }

    private var mask: UInt32 { prefix == 0 ? 0 : ~UInt32(0) << UInt32(32 - prefix) }

    var words: String {
        let base = "\(Subnet.text(network))/\(prefix)"
        return actualPrefix < prefix ? "\(base) (the network is a /\(actualPrefix); only these 256 addresses were swept)" : base
    }

    static func value(_ address: String) -> UInt32? {
        let parts = address.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { return nil }
        return parts.reduce(0) { $0 << 8 | $1 }
    }

    static func text(_ value: UInt32) -> String { (0..<4).reversed().map { String(value >> UInt32($0 * 8) & 0xFF) }.joined(separator: ".") }

    /// The subnet as lamp's command line says it: its network, how much of it is swept, the prefix the network really
    /// has, and this Mac's address on it.
    init?(said: [String: Any]) {
        guard let network = (said["network"] as? String).flatMap(Subnet.value), let mine = (said["mine"] as? String).flatMap(Subnet.value),
              let prefix = said["prefix"] as? Int, let actual = said["actualPrefix"] as? Int, (8...32).contains(prefix) else { return nil }
        self.init(network: network, prefix: prefix, actualPrefix: actual, mine: mine)
    }

    init(network: UInt32, prefix: Int, actualPrefix: Int, mine: UInt32) {
        self.network = network
        self.prefix = prefix
        self.actualPrefix = actualPrefix
        self.mine = mine
    }
}

// MARK: - The neighbor table

/// This Mac's neighbor table, read from the kernel's routing table (what `arp -a` reads), with no program run and
/// nothing sent. It's read here, not by lamp's command line: macOS shows the table only to a process it lets on the
/// local network, and the runtime Lamp carries isn't one, even run by Lamp (it reads the table as empty).
enum Neighbours {
    /// Each neighbor's IPv4 address and hardware address, for those that answered; never multicast or broadcast.
    static func table() -> [String: String] {
        var table: [String: String] = [:]
        for route in routes(flags: 0x400 /* RTF_LLINFO */) {
            guard let address = ipv4(route.destination), route.gateway.count >= 8, Int32(route.gateway[1]) == AF_LINK else { continue }
            let nameLength = Int(route.gateway[5]), length = Int(route.gateway[6])
            guard length == 6, route.gateway.count >= 8 + nameLength + length else { continue }
            let bytes = Array(route.gateway[(8 + nameLength)..<(8 + nameLength + length)])
            guard bytes[0] & 1 == 0, bytes != [UInt8](repeating: 0xFF, count: 6) else { continue }
            table[address] = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
        }
        return table
    }

    private struct Route { var destination: [UInt8]?; var gateway: [UInt8] = []; var interface: UInt16 }

    private static func routes(flags: Int32) -> [Route] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, flags]
        var size = 0
        guard sysctl(&mib, 6, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        size += size / 4   // room for a neighbor added between the two calls
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 6, &buffer, &size, nil, 0) == 0 else { return [] }
        var routes: [Route] = []
        var offset = 0
        let header = MemoryLayout<rt_msghdr>.size
        while offset + header <= size {
            let message = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self) }
            let length = Int(message.rtm_msglen)
            guard length > 0, offset + length <= size else { break }
            var route = Route(destination: nil, interface: message.rtm_index)
            var at = offset + header
            for bit in 0..<8 where message.rtm_addrs & (1 << bit) != 0 {
                guard at < offset + length else { break }
                let saLength = Int(buffer[at])
                let address = Array(buffer[at..<min(at + max(saLength, 1), offset + length)])
                if bit == 0 { route.destination = address }   // RTAX_DST
                if bit == 1 { route.gateway = address }       // RTAX_GATEWAY
                at += saLength == 0 ? 4 : (saLength + 3) & ~3
            }
            routes.append(route)
            offset += length
        }
        return routes
    }

    private static func ipv4(_ address: [UInt8]?) -> String? {
        guard let address, address.count >= 8, Int32(address[1]) == AF_INET else { return nil }
        return address[4..<8].map(String.init).joined(separator: ".")
    }
}

// MARK: - Makers

/// The maker of a device's network hardware, from the first digits of its hardware address, read from the list Lamp
/// ships (`Resources/vendors.xz`, made from the IEEE's registry by `scripts/update-vendors.sh`). Lines are a prefix of
/// six, seven or nine hex digits, a tab and the maker; the longest prefix wins, since a block sold in parts names each.
enum Vendors {
    nonisolated(unsafe) private static var loaded: [String: String]?
    private static let lock = NSLock()

    static var file: URL? { Bundle.main.url(forResource: "vendors", withExtension: "xz") }

    static func maker(of mac: String, in list: [String: String]? = nil) -> String? {
        let hex = mac.split(separator: ":").map { $0.count == 1 ? "0" + $0 : String($0) }.joined().uppercased()
        guard hex.count == 12, !isRandomised(mac) else { return nil }
        let list = list ?? all()
        for length in [9, 7, 6] { if let maker = list[String(hex.prefix(length))] { return maker } }
        return nil
    }

    /// A locally administered address (the second bit of its first byte): one the device made up, as phones,
    /// tablets and computers do for each Wi‑Fi network, rather than one its maker was given.
    static func isRandomised(_ mac: String) -> Bool {
        guard let first = mac.split(separator: ":").first, let byte = UInt8(first, radix: 16) else { return false }
        return byte & 0x02 != 0
    }

    static func all() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        if let loaded { return loaded }
        let list = file.flatMap(read) ?? [:]
        loaded = list
        return list
    }

    static func read(_ url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url), let text = try? (data as NSData).decompressed(using: .lzma) as Data else { return nil }
        var list: [String: String] = [:]
        for line in String(decoding: text, as: UTF8.self).split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            list[String(line[..<tab])] = String(line[line.index(after: tab)...])
        }
        return list
    }
}
