import Darwin
import Foundation
import dnssd

/// Everything on the person's home network, one record per address, for when the person is looking for devices (Your
/// Devices, Add a New Device, `network_devices`): never at launch or on a timer. SSDP and the integrations find what
/// Lamp can work with; this finds the rest, so the list can say what else is there and the agent can work out what
/// each one is. It only reads: one small datagram to each address of this Mac's own subnet, so the Mac's neighbour
/// table fills (a phone that ignores everything else still answers the Mac's ARP), that table, the maker of each
/// hardware address from the IEEE's registry (`Vendors`), and every Bonjour service on the network. Nothing is kept on
/// disk: the names a network holds are often people's ("…'s iPhone"), so they're shown on this Mac and told to the
/// agent the person uses, and go nowhere else.
struct NetworkHost: Hashable, Identifiable {
    var id: String { address }
    let address: String
    /// Its hardware address, "38:b4:d3:31:25:e0", from this Mac's neighbour table.
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
/// what the device is (model keys only; nothing that identifies the device or the person further).
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

    static let modelKeys: Set<String> = ["md", "model", "am", "ty", "usb_MFG", "usb_MDL", "product", "manufacturer"]
}

enum HomeNetwork {
    /// What a look on the network found besides SSDP: the hosts of this Mac's subnet with their hardware addresses, and
    /// every Bonjour service. `swept` says how much of the subnet was swept, for the agent: on a network bigger than a
    /// /24 only the 256 addresses around this Mac's are.
    struct Look {
        var hosts: [NetworkHost] = []
        var swept: Subnet?
    }

    /// Sweeps this Mac's subnet, browses Bonjour meanwhile, then reads the neighbour table. Sends nothing anywhere else.
    static func look() async -> Look {
        async let services = Bonjour.everything()
        let subnet = Subnet.current()
        if let subnet { await Sweep.run(subnet) }
        let table = Neighbours.table()
        let gateway = Neighbours.gateway()
        let mine = TVs.macAddresses()
        var hosts: [String: NetworkHost] = [:]
        for (address, mac) in table where subnet?.contains(address) ?? DeviceAddress.isPrivate(address) || mine.contains(address) {
            var host = NetworkHost(address: address, mac: mac)
            host.randomised = Vendors.isRandomised(mac)
            host.vendor = host.randomised ? nil : Vendors.maker(of: mac)
            hosts[address] = host
        }
        for service in await services {
            for address in service.addresses where subnet?.contains(address) ?? DeviceAddress.isPrivate(address) || mine.contains(address) {
                hosts[address, default: NetworkHost(address: address)].services.append(service.service)
            }
        }
        for address in hosts.keys {
            hosts[address]?.isThisMac = mine.contains(address)
            hosts[address]?.isGateway = address == gateway
        }
        return Look(hosts: hosts.values.sorted { order($0.address) < order($1.address) }, swept: subnet)
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
    static func sameNetwork(as swept: Subnet?, router: String?) -> Bool {
        guard let swept, let now = Subnet.current(), now.network == swept.network, now.prefix == swept.prefix else { return false }
        guard let router else { return true }
        return Neighbours.gateway().flatMap { Neighbours.table()[$0] } == router
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
        var device = Device(id: "found:\(host.address)", kind: .other, maker: maker, model: model.isEmpty ? maker : model,
                            modelID: "", name: name, os: "", osVersion: "", reach: .network)
        device.address = host.address
        return device
    }

    /// The list as Your Devices shows it: what Lamp makes apps for or controls, in the order Lamp found them; then the
    /// devices Lamp could learn; then every other host on the network, and a count of those with private addresses
    /// that say nothing else, since nothing tells one such phone from another.
    struct List {
        var works: [Device] = []
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
                        works.append(device)
                    } else {
                        couldLearn.append(device)
                    }
                } else {
                    works.append(device)
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

    /// The subnet of the interface the default route uses, when it's a private IPv4 one.
    static func current() -> Subnet? {
        guard let index = Neighbours.gatewayInterface(), let name = interfaceName(index) else { return nil }
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard String(cString: entry.ifa_name) == name, let address = entry.ifa_addr, let netmask = entry.ifa_netmask,
                  Int32(address.pointee.sa_family) == AF_INET else { continue }
            let mine = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            return make(mine: mine, mask: mask)
        }
        return nil
    }

    /// The subnet to sweep for an address and its mask; nil for one that isn't on a private network.
    static func make(mine: UInt32, mask: UInt32) -> Subnet? {
        let actual = mask.nonzeroBitCount
        guard actual >= 8, actual <= 30 else { return nil }
        let prefix = max(actual, widest)
        let network = mine & (~UInt32(0) << UInt32(32 - prefix))
        let subnet = Subnet(network: network, prefix: prefix, actualPrefix: actual, mine: mine)
        return DeviceAddress.onNetwork(text(mine)) ? subnet : nil
    }

    private static func interfaceName(_ index: UInt16) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        return if_indextoname(UInt32(index), &buffer).map { String(cString: $0) }
    }
}

/// One datagram to each address of the subnet, so the Mac asks who has it (ARP) and its neighbour table fills. The
/// datagram is one byte to the discard port (9), which nothing answers; it's sent a few addresses at a time, paced.
enum Sweep {
    static let batch = 16
    static let pause: Duration = .milliseconds(25)
    /// How long the neighbours have to answer the Mac's ARP after the last datagram.
    static let settle: Duration = .milliseconds(1500)

    static func run(_ subnet: Subnet) async {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let addresses = subnet.addresses
        var start = 0
        while start < addresses.count {
            for value in addresses[start..<min(start + batch, addresses.count)] {
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = UInt16(9).bigEndian
                address.sin_addr.s_addr = value.bigEndian
                var byte: UInt8 = 0
                _ = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, &byte, 1, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
            }
            start += batch
            try? await Task.sleep(for: pause)
        }
        try? await Task.sleep(for: settle)
    }
}

// MARK: - The neighbour table

/// This Mac's neighbour table and default route, read from the kernel's routing table (what `arp -a` and `route` read),
/// with no program run and nothing sent.
enum Neighbours {
    /// Each neighbour's IPv4 address and hardware address, for those that answered; never multicast or broadcast.
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

    static func gateway() -> String? {
        routes(flags: RTF_GATEWAY).first { ipv4($0.destination) == "0.0.0.0" }.flatMap { ipv4($0.gateway) }
    }

    static func gatewayInterface() -> UInt16? {
        routes(flags: RTF_GATEWAY).first { ipv4($0.destination) == "0.0.0.0" && ipv4($0.gateway) != nil }?.interface
    }

    private struct Route { var destination: [UInt8]?; var gateway: [UInt8] = []; var interface: UInt16 }

    private static func routes(flags: Int32) -> [Route] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, flags]
        var size = 0
        guard sysctl(&mib, 6, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        size += size / 4   // room for a neighbour added between the two calls
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

// MARK: - Bonjour, all of it

/// Every Bonjour service on the network: the types it offers (`_services._dns-sd._udp`), the services of each, and each
/// one's host, address and record, all read with mDNS (`dns_sd`) and no connection to the device.
enum Bonjour {
    struct Found: Hashable {
        let service: BonjourService
        let addresses: [String]
    }

    static let browseFor: Duration = .seconds(3)
    /// Browsed whether or not the meta-query names them: a device that's asleep often misses that one answer, and
    /// these are the services that say most about what a quiet device is (a Cast device, a printer, a gadget's web page).
    static let alwaysBrowse = ["_googlecast._tcp", "_ipp._tcp", "_printer._tcp", "_http._tcp", "_esphomelib._tcp"]

    static func everything() async -> [Found] {
        let types = await browse("_services._dns-sd._udp").map { name, type in
            // The meta-query's answers are "_airplay" in "_tcp.local.".
            name + "." + (type.components(separatedBy: ".").first ?? "_tcp")
        }
        let unique = Array(Set(types + alwaysBrowse)).filter { $0.range(of: #"^_[A-Za-z0-9-]{1,40}\._(tcp|udp)$"#, options: .regularExpression) != nil }.prefix(60)
        var services: [BonjourService] = []
        await withTaskGroup(of: [BonjourService].self) { group in
            for type in unique {
                group.addTask {
                    var found: [BonjourService] = []
                    let instances = Array(Set(await browse(type).map(\.name))).prefix(40)
                    await withTaskGroup(of: BonjourService?.self) { each in
                        for name in instances { each.addTask { await resolve(name: name, type: type) } }
                        for await one in each { if let one { found.append(one) } }
                    }
                    return found
                }
            }
            for await some in group { services += some }
        }
        // Each host's address is looked up once for all its services: a device with many (a printer has eight) answered
        // some of them and not others when each asked for itself.
        var byHost: [String: [String]] = [:]
        await withTaskGroup(of: (String, [String]).self) { group in
            for host in Set(services.map(\.host)) { group.addTask { (host, await addresses(of: host)) } }
            for await (host, addresses) in group { byHost[host] = addresses }
        }
        return services.compactMap { service in
            byHost[service.host].flatMap { $0.isEmpty ? nil : Found(service: service, addresses: $0) }
        }
    }

    /// The names a browse hears for a while, with the type each answered for.
    private static func browse(_ type: String) async -> [(name: String, type: String)] {
        final class Heard: @unchecked Sendable { var items: [(String, String)] = []; let lock = NSLock() }
        let heard = Heard()
        let queue = DispatchQueue(label: "lamp.bonjour.browse")
        var ref: DNSServiceRef?
        let reply: DNSServiceBrowseReply = { _, flags, _, error, name, type, _, context in
            guard error == DNSServiceErrorType(kDNSServiceErr_NoError), flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0, let name, let type, let context else { return }
            let heard = Unmanaged<Heard>.fromOpaque(context).takeUnretainedValue()
            heard.lock.lock(); heard.items.append((String(cString: name), String(cString: type))); heard.lock.unlock()
        }
        let retained = Unmanaged.passRetained(heard)
        guard DNSServiceBrowse(&ref, 0, 0, type, "local.", reply, retained.toOpaque()) == DNSServiceErrorType(kDNSServiceErr_NoError), let ref else {
            retained.release()
            return []
        }
        DNSServiceSetDispatchQueue(ref, queue)
        try? await Task.sleep(for: browseFor)
        queue.sync { DNSServiceRefDeallocate(ref) }
        retained.release()
        return heard.lock.withLock { heard.items }
    }

    /// One service's host and record, waited for up to three seconds.
    private static func resolve(name: String, type: String) async -> BonjourService? {
        final class Resolved: @unchecked Sendable { var host: String?; var txt: [String: String] = [:]; let lock = NSLock() }
        let resolved = Resolved()
        let queue = DispatchQueue(label: "lamp.bonjour.resolve")
        let retained = Unmanaged.passRetained(resolved)
        defer { retained.release() }
        var ref: DNSServiceRef?
        let reply: DNSServiceResolveReply = { _, _, _, error, fullName, host, _, length, record, context in
            guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let host, let context else { return }
            let resolved = Unmanaged<Resolved>.fromOpaque(context).takeUnretainedValue()
            var txt: [String: String] = [:]
            if let record {
                let data = Data(bytes: record, count: Int(length))
                for (key, value) in NetService.dictionary(fromTXTRecord: data) where BonjourService.modelKeys.contains(key) {
                    // A Cast device's "md" is its model; AirPlay's is the kinds of metadata it takes.
                    if key == "md", !(fullName.map { String(cString: $0) } ?? "").contains("._googlecast._tcp.") { continue }
                    let text = String(decoding: value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty, text.count <= 80, !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { txt[key] = text }
                }
            }
            resolved.lock.lock(); resolved.host = String(cString: host); resolved.txt = txt; resolved.lock.unlock()
        }
        guard DNSServiceResolve(&ref, 0, 0, name, type, "local.", reply, retained.toOpaque()) == DNSServiceErrorType(kDNSServiceErr_NoError), let ref else { return nil }
        DNSServiceSetDispatchQueue(ref, queue)
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if (resolved.lock.withLock { resolved.host }) != nil { break }
        }
        queue.sync { DNSServiceRefDeallocate(ref) }
        guard let host = resolved.lock.withLock({ resolved.host }) else { return nil }
        return BonjourService(type: type, name: name, host: host, txt: resolved.lock.withLock { resolved.txt })
    }

    /// A Bonjour host's IPv4 addresses, waited for up to three seconds.
    private static func addresses(of host: String) async -> [String] {
        final class Heard: @unchecked Sendable { var addresses: [String] = []; let lock = NSLock() }
        let heard = Heard()
        let queue = DispatchQueue(label: "lamp.bonjour.address")
        let retained = Unmanaged.passRetained(heard)
        defer { retained.release() }
        var lookup: DNSServiceRef?
        let reply: DNSServiceGetAddrInfoReply = { _, _, _, error, _, socket, _, context in
            guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let socket, let context, Int32(socket.pointee.sa_family) == AF_INET else { return }
            let heard = Unmanaged<Heard>.fromOpaque(context).takeUnretainedValue()
            let text = socket.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { String(cString: inet_ntoa($0.pointee.sin_addr)) }
            heard.lock.lock(); if !heard.addresses.contains(text) { heard.addresses.append(text) }; heard.lock.unlock()
        }
        guard DNSServiceGetAddrInfo(&lookup, 0, 0, DNSServiceProtocol(kDNSServiceProtocol_IPv4), host, reply, retained.toOpaque()) == DNSServiceErrorType(kDNSServiceErr_NoError),
              let lookup else { return [] }
        DNSServiceSetDispatchQueue(lookup, queue)
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if !(heard.lock.withLock { heard.addresses }).isEmpty { break }
        }
        queue.sync { DNSServiceRefDeallocate(lookup) }
        return heard.lock.withLock { heard.addresses }
    }
}
