import Foundation

/// `network_devices`: what's on the person's home network, as Lamp's own look finds it (the TV kits, the integrations
/// and every other device that answers SSDP), for a wish that controls, plays to or reads such devices. The agent
/// starts from what's there rather than asking the person what they own, and works out from what each device says of
/// itself how an app can reach it.
enum NetworkDevices {
    @MainActor static func answer() async -> (Int, [String: Any]) {
        let devices = await Store.shared.devicesNow()
        let refused = await Task.detached { DeviceProbe.localNetworkRefused() }.value
        return (200, ["text": describe(devices, integrations: Integrations.all(), refused: refused)])
    }

    /// The devices on the network, one paragraph each. Phones, the Mac and anything plugged in are left out: they're
    /// where apps run, which the device line says.
    static func describe(_ devices: [Device], integrations: [Integration], refused: Bool = false) -> String {
        if refused {
            return "Lamp can't look: macOS keeps it off the local network. Tell the person to turn on Lamp in System Settings → "
                + "Privacy & Security → Local Network, then call this again. Don't look around the network yourself meanwhile."
        }
        let devices = devices.filter { $0.reach == .network && ($0.kind.isTV || $0.kind == .other) }
        let found = devices.filter(\.connected), away = devices.filter { !$0.connected }
        let how = "Lamp looked just now with an SSDP search of this Mac's network, its TV kits and its device integrations. "
            + "A device that answers only Bonjour or nothing at all (many speakers, plugs and lights) isn't listed: when one "
            + "the person names is missing, look for it yourself before asking them about it."
        func lines(_ devices: [Device]) -> String {
            devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map { device in
                var line = "- \(one(device.name))"
                // "Roku Express" by Roku is said once.
                let what = device.model.hasPrefix(device.maker) ? device.model : [device.maker, device.model].filter { !$0.isEmpty }.joined(separator: " ")
                if !what.isEmpty, what != device.name { line += " (\(one(what)))" }
                if let address = device.address { line += " at \(address)" }
                line += ". " + known(device, integrations: integrations)
                if let said = device.discovery.flatMap(ssdp) { line += " " + said }
                return line
            }.joined(separator: "\n")
        }
        var text = found.isEmpty ? "Nothing answered on the network." : "On the person's network now:\n" + lines(found)
        // Kept from before and not here now: another home, or switched off.
        if !away.isEmpty { text += "\n\nKnown from before, not on this network now:\n" + lines(away) }
        return text + "\n\n" + how
    }

    /// What Lamp already has for a device: a building block that controls it from an app, or only a way to put apps
    /// on it, or nothing, in which case how an app reaches it is for the agent to work out.
    static func known(_ device: Device, integrations: [Integration]) -> String {
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
