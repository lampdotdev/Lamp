import SwiftUI
import LampSidebarKit

/// The person's devices down the desk's side, under the wishes' filters, since a wish for the TV or the phone is one
/// Lamp is made for and Settings is no place to find that out. Until Lamp has looked on the network it's an invitation
/// to, whose button is the look that has macOS ask about the local network; from then on the desk looks each time it's
/// shown, and the list is the devices Lamp makes apps for, the likeliest first. A ready one, or one only found that
/// Lamp has nothing to set up for, puts itself in the bar; one that isn't ready takes its next step; the rest of the
/// network is in Settings → Your Devices.
struct DeskDevices: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Store.localNetworkAskedKey) private var asked = false
    @AppStorage("appleTeam") private var team = ""
    @AppStorage("settingsTab") private var settingsTab = "building"
    @Environment(\.openSettings) private var openSettings
    @State private var adding = false
    /// Puts "for my <device>" in the wish bar.
    let wishFor: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("YOUR DEVICES")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Paper.label)
                .padding(.horizontal, 10).padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            if asked { list } else { invitation }
        }
        .sheet(isPresented: $adding) { AddDeviceSheet() }
    }

    private var invitation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(["iphone", "ipad", "tv", "gamecontroller", "hifispeaker", "photo"], id: \.self) {
                    Image(systemName: $0)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(Paper.muted)
            .accessibilityHidden(true)
            Text("Run it on your TV, phone, Xbox and more")
                .font(.callout)
                .foregroundStyle(Paper.muted)
                .fixedSize(horizontal: false, vertical: true)
            if store.lookingForDevices {
                LookingForDevices()
            } else {
                Button { store.refreshDevices() } label: { Label("Find My Devices", systemImage: "dot.radiowaves.left.and.right") }
                    .buttonStyle(PaperButtonStyle(.ink))
            }
        }
        .padding(.horizontal, 10)
    }

    private var list: some View {
        let found = HomeNetwork.List(devices: [store.thisMac].compactMap { $0 } + store.devices, hosts: store.hosts)
        let ranked = Self.ranked(found, team: team)
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(ranked) { device in row(device) }
            // What Lamp could only learn (a server, an appliance) is counted, never listed: it's in Settings.
            if !found.couldLearn.isEmpty {
                DeskChip(help: "All your devices, in Settings", action: showAll) {
                    Image(systemName: "ellipsis").frame(width: 18)
                    Text("\(found.couldLearn.count) More").foregroundStyle(Paper.muted)
                }
            }
            DeskChip(help: "Plug in a phone or tablet, or set up another device", action: { adding = true }) {
                // While Lamp looks, the plus turns, so the list doesn't move for it.
                if store.lookingForDevices {
                    ProgressView().controlSize(.small).frame(width: 18, height: 16).help("Looking for devices…")
                } else {
                    Image(systemName: "plus").frame(width: 18)
                }
                Text("Add a Device")
            }
            .foregroundStyle(Paper.muted)
            if store.localNetworkRefused, !store.lookingForDevices { LocalNetworkRefused().padding(.top, 6) }
        }
        .animation(.easeOut(duration: 0.25), value: ranked.map(\.id))
    }

    /// `found` is a device only seen on the network that Lamp has no setup for (a speaker, say): an app talks to it
    /// there directly, so there's nothing to set up, only something to wish for.
    enum Standing: Equatable { case here, ready, setUp, found, away }

    static func state(of device: Device, team: String) -> Standing {
        if device.id == Device.macID { return .here }
        if device.isAway { return .away }
        if device.kind == .other, !device.isSetUp, device.integration == nil { return .found }
        if !device.isSetUp { return .setUp }
        if case .needs = device.setup(team: team) { return .setUp }
        return .ready
    }

    /// The devices the shelf offers, likeliest to be wished for first: this Mac, then the person's own (ready before
    /// part-way set up, before away), then what was only found that Lamp makes apps for or controls. Within each, the
    /// devices people make most for: a phone or tablet, a TV or a box on it, a watch, Android, then what an app only
    /// controls (a speaker). What Lamp could only learn (a server, an appliance) isn't offered here, only counted.
    static func ranked(_ list: HomeNetwork.List, team: String) -> [Device] {
        func standing(_ device: Device) -> Int {
            switch state(of: device, team: team) {
            case .here: return 0
            case .ready: return 1
            case .setUp: return device.isSetUp ? 2 : 4
            case .found: return 4
            case .away: return 3
            }
        }
        func kind(_ device: Device) -> Int {
            switch device.kind {
            case .mac: return 0
            case .iphone: return 1
            case .ipad: return 2
            case .samsungTV, .lgTV: return 3
            case .other: return device.integration != nil ? 3 : 7
            case .watch: return 4
            case .android: return 5
            case .androidEmulator: return 6
            }
        }
        return (list.works + list.possible).enumerated()
            .sorted { (standing($0.element), kind($0.element), $0.offset) < (standing($1.element), kind($1.element), $1.offset) }
            .map(\.element)
    }

    /// What a ready device is called in a wish: a phone or watch by what it is ("my iPhone"), since its own name is
    /// often its owner's; a TV or another device by its name ("my Living Room TV"). Android's say whether they're a TV
    /// and whether they're the emulator, which is all adb tells of them: a phone and a tablet are both a device.
    static func words(for device: Device) -> String {
        let tv = device.features.contains("tv")
        switch device.kind {
        case .iphone, .ipad, .watch: return device.kind.name
        case .android: return tv ? "Android TV" : "Android device"
        case .androidEmulator: return tv ? "Android TV emulator" : "Android emulator"
        default: return device.name
        }
    }

    /// A device's name on its chip, short and plain. One only found goes by what it is ("Sonos Play:1"); the person's
    /// own go by their names. Either way, the parts a network name strings together that mean nothing to a person (an
    /// address, a serial like "RINCON_38420B99FAFA01400") are left out: what else is known is in its tip.
    static func label(_ device: Device) -> String {
        if !device.isSetUp, !device.model.isEmpty, !isNoise(device.model) {
            // A model of a few words says what it is ("SYMFONISK Bookshelf"); one word alone ("Play:1") is said with its
            // maker's own name.
            let maker = brand(device.maker)
            return device.model.contains(" ") || maker.isEmpty || device.model.localizedCaseInsensitiveContains(maker)
                ? device.model : "\(maker) \(device.model)"
        }
        return names(device.name).first ?? device.kind.name
    }

    /// A maker by the name people call it: "Sonos" for "Sonos, Inc.".
    static func brand(_ maker: String) -> String {
        guard !isNoise(maker) else { return "" }
        let first = maker.components(separatedBy: ",").first ?? maker
        return first.replacingOccurrences(of: #"\s+(Inc\.?|LLC|Ltd\.?|Corporation|Corp\.?|Co\.?|GmbH|AG|S\.?A\.?)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// The parts of a name that mean something to a person: "Kitchen" of "192.168.1.5 - Kitchen - RINCON_…".
    static func names(_ name: String) -> [String] {
        name.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !isNoise($0) }
    }

    /// An address, or an identifier: long, with no lowercase letter and no space ("RINCON_7828CA96A6DE01400").
    static func isNoise(_ part: String) -> Bool {
        if part.isEmpty || Subnet.value(part) != nil || NetworkHost.isID(part) { return true }
        return part.count >= 12 && !part.contains(" ") && part.rangeOfCharacter(from: .lowercaseLetters) == nil
    }

    private func row(_ device: Device) -> some View {
        let state = Self.state(of: device, team: team)
        let name = state == .here ? "This Mac" : Self.label(device)
        return DeskChip(help: name, tip: tip(device, name: name, state: state), action: state == .here ? nil : { act(device, state: state) }) {
            Image(systemName: device.symbol).frame(width: 18)
            Text(name).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            switch state {
            case .here, .ready:
                DeviceDot(color: .green)
            case .setUp:
                Text("Set up").font(.caption.weight(.bold)).foregroundStyle(Paper.label)
                DeviceDot(color: DeviceDot.amber)
            case .found, .away:
                EmptyView()
            }
        }
        .opacity(state == .away ? 0.5 : 1)
        .accessibilityValue(state == .setUp ? "Not set up" : state == .away ? "Not on this network" : state == .found ? "Found on your network" : "Ready")
    }

    /// What's known of a device, for its tip: what it is, what it's called at home, where it is, where its setup
    /// stands and what a click does. Never its address: that's for Settings' list and the agent.
    private func tip(_ device: Device, name: String, state: Standing) -> DeviceTip {
        var lines: [String] = []
        let what = [Self.brand(device.maker), device.model].filter { !$0.isEmpty && !Self.isNoise($0) }
        let model = what.count == 2 && what[1].localizedCaseInsensitiveContains(what[0]) ? what[1] : what.joined(separator: " ")
        // Software is said for what people know by it (macOS 27, iOS 27), not a speaker's firmware.
        let os = device.os.isEmpty || ![.mac, .iphone, .ipad, .watch, .android].contains(device.kind) ? "" : " · \(device.os) \(device.osVersion)".trimmingCharacters(in: .whitespaces)
        if !model.isEmpty, model != name || !os.isEmpty { lines.append(model + (os.isEmpty ? "" : " " + os)) }
        // The names it goes by: often a room ("Kitchen"), which tells two of one model apart. Its own name, which every
        // look reads, and those a whole look found for its address.
        let host = device.address.flatMap { address in store.hosts.first { $0.address == address } }
        var called: [String] = []
        for each in Self.names(device.name) + (host?.names ?? [])
        where each != name && !model.localizedCaseInsensitiveContains(each) && !called.contains(where: { $0.caseInsensitiveCompare(each) == .orderedSame }) {
            called.append(each)
        }
        if !called.isEmpty { lines.append("Called \(called.prefix(2).joined(separator: ", ")) on your network") }
        switch device.reach {
        case .thisMac: break
        case .cable: lines.append("Plugged into this Mac")
        case .network: lines.append(device.isSetUp ? "On your network" : "Found on your network")
        case .throughPhone: lines.append("Through its iPhone")
        }
        switch state {
        case .here:
            return DeviceTip(title: name, lines: lines, status: ("Ready", .green), hint: nil)
        case .ready:
            return DeviceTip(title: name, lines: lines, status: ("Ready", .green), hint: "Click to wish for something for it.")
        case .setUp:
            var step = "Not set up yet"
            if device.isSetUp, case .needs(let next) = device.setup(team: team) { step = next }
            return DeviceTip(title: name, lines: lines, status: (step, DeviceDot.amber), hint: "Click to set it up.")
        case .found:
            return DeviceTip(title: name, lines: lines, status: nil, hint: "Click to wish for something for it.")
        case .away:
            return DeviceTip(title: name, lines: lines, status: ("Not on this network just now", .secondary), hint: "Click to see all your devices.")
        }
    }

    private func act(_ device: Device, state: Standing) {
        switch state {
        case .here: break
        case .ready: wishFor(Self.words(for: device))
        case .found: wishFor(Self.label(device))
        case .setUp: if !DeviceNextStep.takeFurther(device, store: store) { showAll() }
        case .away: showAll()
        }
    }

    private func showAll() {
        settingsTab = "building"
        openSettings()
    }
}

/// A device's state as a dot: green when it's ready, amber when it needs setting up.
struct DeviceDot: View {
    let color: Color
    static let amber = Color(red: 1, green: 0.7, blue: 0.1)

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
    }
}

/// One line of the desk's device list, lit under the pointer. One with no action is only shown.
struct DeskChip<Content: View>: View {
    let help: String
    /// Shown a moment after the pointer comes onto it, in place of the plain help.
    var tip: DeviceTip? = nil
    let action: (() -> Void)?
    @ViewBuilder let content: Content
    @State private var hovered = false
    @State private var tipShown = false

    var body: some View {
        let lit = hovered && action != nil
        let label = HStack(spacing: 9) { content }
            .font(.system(size: 13.5))
            .foregroundStyle(Paper.ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(Paper.ink.opacity(lit ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .help(tip == nil ? help : "")
            .task(id: hovered) {
                guard hovered, tip != nil else { tipShown = false; return }
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled { tipShown = true }
            }
            .popover(isPresented: $tipShown, arrowEdge: .trailing) {
                if let tip { tip.interactiveDismissDisabled() }
            }
        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label.accessibilityElement(children: .combine)
        }
    }
}

/// A device's tip on the shelf: its name, what's known of it a line each, where its setup stands and what a click does.
struct DeviceTip: View {
    let title: String
    let lines: [String]
    let status: (words: String, color: Color)?
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            ForEach(lines, id: \.self) { Text($0).foregroundStyle(.secondary) }
            if let status {
                HStack(spacing: 6) {
                    DeviceDot(color: status.color)
                    Text(status.words)
                }
                .padding(.top, 2)
            }
            if let hint {
                Text(hint).font(.callout).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
        .font(.body)
        .fixedSize()
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}
