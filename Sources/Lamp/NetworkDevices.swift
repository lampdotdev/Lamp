import Foundation

/// `network_devices`: what's on the person's home network, as Lamp's own look finds it (the TV kits, the integrations,
/// every other device that answers SSDP, and every host the sweep and Bonjour find, `HomeNetwork`), for a wish that
/// controls, plays to or reads such devices, and for working out what a device the person asks about is. The agent
/// starts from what's there rather than asking the person what they own, and works out from what each device says of
/// itself how an app can reach it.
enum NetworkDevices {
    @MainActor static func answer() async -> (Int, [String: Any]) {
        let (devices, done) = await Store.shared.devicesNow()
        guard done else {
            return (200, ["text": "Lamp's look around the network is still going (a device is slow to answer). Call this again in a moment; until then, don't take the network to be empty."])
        }
        return (200, ["text": describe(devices, integrations: Integrations.all(), hosts: Store.shared.hosts, swept: Store.shared.swept,
                                       refused: Store.shared.localNetworkRefused)])
    }

    /// The devices on the network, one paragraph each. Phones, the Mac and anything plugged in are left out: they're
    /// where apps run, which the device line says.
    static func describe(_ devices: [Device], integrations: [Integration], hosts: [NetworkHost] = [], swept: Subnet? = nil,
                         refused: Bool = false) -> String {
        if refused {
            return "Lamp can't look: macOS keeps it off the local network. Tell the person to turn on Lamp in System Settings → "
                + "Privacy & Security → Local Network, then call this again. Don't look around the network yourself meanwhile."
        }
        let devices = devices.filter { $0.reach == .network && ($0.kind.isTV || $0.kind == .other) }
        let found = devices.filter(\.connected), away = devices.filter { !$0.connected }
        let byAddress = Dictionary(hosts.map { ($0.address, $0) }, uniquingKeysWith: { first, _ in first })
        let how = hosts.isEmpty
            ? "Lamp looked just now with an SSDP search of this Mac's network, its TV kits and its device integrations. "
                + "A device that answers only Bonjour or nothing at all (many speakers, plugs and lights) isn't listed: when one "
                + "the person names is missing, look for it yourself before asking them about it."
            : "Lamp looked just now: an SSDP search, its TV kits and device integrations, every Bonjour service, and a sweep of "
                + (swept.map { "this Mac's subnet, \($0.words)" } ?? "this Mac's subnet")
                + " that filled the Mac's neighbor table, with each hardware address's maker from the IEEE's registry. "
                + "When the person asks what something is, or asks Lamp to learn one, work out what each host is from these facts "
                + "and say how sure you are: the gateway is the router; the hardware's maker says what it usually makes; a "
                + "private (randomized) hardware address is a phone, tablet or computer, and nothing tells those apart, so count "
                + "them rather than guess whose is whose. The names here come from the person's network and are often people's: "
                + "use them only in what you say to the person, never in an app's code or files, an integration, or anything sent elsewhere."
        func lines(_ devices: [Device]) -> String {
            devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map { device in
                var line = "- \(one(device.name))"
                // "Roku Express" by Roku is said once.
                let what = device.model.hasPrefix(device.maker) ? device.model : [device.maker, device.model].filter { !$0.isEmpty }.joined(separator: " ")
                if !what.isEmpty, what != device.name { line += " (\(one(what)))" }
                if let address = device.address { line += " at \(address)" }
                line += ". " + known(device, integrations: integrations, host: device.address.flatMap { byAddress[$0] })
                if let said = device.discovery.flatMap(ssdp) { line += " " + said }
                if let host = device.address.flatMap({ byAddress[$0] }) { line += " Its host: " + HomeNetwork.facts(host) + "." }
                return line
            }.joined(separator: "\n")
        }
        var text = found.isEmpty ? "Nothing answered on the network." : "On the person's network now:\n" + lines(found)
        // Kept from before and not here now: another home, or switched off.
        if !away.isEmpty { text += "\n\nKnown from before, not on this network now:\n" + lines(away) }
        // Every other address that answered: the router, this Mac, printers, appliances, phones.
        let listed = Set(found.compactMap(\.address))
        let rest = hosts.filter { !listed.contains($0.address) }
        if !rest.isEmpty { text += "\n\nEverything else on the network, which Lamp has nothing for:\n" + rest.map { "- " + HomeNetwork.facts($0) }.joined(separator: "\n") }
        return text + "\n\n" + how
    }

    /// What Lamp already has for a device: a building block that controls it from an app, or only a way to put apps
    /// on it, or nothing, in which case how an app reaches it is for the agent to work out.
    static func known(_ device: Device, integrations: [Integration], host: NetworkHost? = nil) -> String {
        if let controls = HomeNetwork.controls(device, host: host), device.integration == nil, !device.kind.isTV { return controls }
        if device.integration == "roku" {
            return "An app on this Mac or an iPhone controls it with `LampRoku` (LampSupport.swift): keys, apps, typing, what's playing, and a Roku TV's power, volume and input."
        }
        if device.kind.isTV { return "Lamp puts TV apps on it; nothing of Lamp's controls it from another app yet." }
        if let id = device.integration {
            let integration = integrations.first { $0.id == id }
            let name = integration?.name ?? id
            return integration?.app != nil
                ? "Lamp puts apps on it through its \(name) integration; nothing of Lamp's controls it from another app yet."
                : "Lamp finds it through its \(name) integration; nothing of Lamp's controls it from an app yet."
        }
        return "Lamp has nothing for it yet."
    }

    /// What a device said to the SSDP search (`Device.discovery`: "<target> (<server>)" for each answer), with each
    /// server said once and the per-device uuid targets left out, since every answer carries the same few.
    static func ssdp(_ discovery: String) -> String? {
        var servers: [String] = [], targets: [String] = []
        for answer in discovery.components(separatedBy: "; ") {
            let parts = answer.split(separator: "(", maxSplits: 1)
            let target = parts.first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            let server = parts.count > 1 ? String(parts[1].dropLast()).trimmingCharacters(in: .whitespaces) : ""
            if !target.isEmpty, !target.hasPrefix("uuid:"), !targets.contains(target) { targets.append(target) }
            if !server.isEmpty, !servers.contains(server) { servers.append(server) }
        }
        guard !servers.isEmpty || !targets.isEmpty else { return nil }
        var said = "It answered SSDP"
        if !servers.isEmpty { said += " as \(one(servers.joined(separator: ", ")).prefix(160))" }
        if !targets.isEmpty { said += ", for \(one(targets.prefix(8).joined(separator: ", ")))" }
        return said + "."
    }

    private static func one(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }
}
