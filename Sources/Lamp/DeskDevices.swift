import SwiftUI
import LampSidebarKit

/// The person's devices down the desk's side, under the wishes' filters, since a wish for the TV or the phone is one
/// Lamp is made for and Settings is no place to find that out. Until Lamp has looked on the network it's an invitation
/// to, whose button is the look that has macOS ask about the local network; from then on the desk looks each time it's
/// shown, and the list is the devices Lamp makes apps for, the likeliest first. A ready one, or one only found that
/// Lamp has nothing to set up for, puts itself in the bar; one that isn't ready takes its next step. The rest of the
/// network opens under More, in place, and a right-click has what can be done to a device: Set Up…, Reconnect…, Forget….
struct DeskDevices: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Store.localNetworkAskedKey) private var asked = false
    @AppStorage("appleTeam") private var team = ""
    @State private var adding = false
    /// Everything else on the network is shown, under the devices offered.
    @State private var showingAll = false
    @State private var forgetting: Device?
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
        .sheet(isPresented: $adding) { AddDeviceSheet(onPaper: true) }
        .confirmationDialog(forgetting.map { "Forget \($0.name)?" } ?? "", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
            Button("Forget", role: .destructive) { if let device = forgetting { forget(device) } }
        } message: {
            Text("Lamp forgets how to reach it and what you typed for it. To use it again, set it up from the start.")
        }
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
            // What Lamp could only learn (a server, an appliance), then every other host on the network, opened in place.
            // Opening it looks over the whole network (`refreshDevices(everything:)`), which only then knows its hosts.
            if showingAll {
                ForEach(found.couldLearn) { device in row(device) }
                ForEach(found.others) { host in hostRow(host) }
                if found.unnamed > 0 {
                    Text(found.unnamed == 1 ? "1 more with a private address, most likely a phone, tablet or computer"
                         : "\(found.unnamed) more with private addresses, most likely phones, tablets and computers")
                        .font(.system(size: 12)).foregroundStyle(Paper.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                }
            }
            let more = found.couldLearn.count + found.others.count + found.unnamed
            DeskChip(help: showingAll ? "Show only the devices Lamp makes apps for" : "Everything else on your network", action: {
                withAnimation(.easeOut(duration: 0.25)) { showingAll.toggle() }
                if showingAll { store.refreshDevices(everything: true) }
            }) {
                Image(systemName: showingAll ? "chevron.up" : "ellipsis").frame(width: 18)
                Text(showingAll ? "Fewer" : more > 0 ? "\(more) More" : "More").foregroundStyle(Paper.muted)
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

    /// A host nothing of Lamp's works with: what it is, and the names it goes by on the network. A click sets it up: the
    /// agent works out what it is and whether anything can reach it. The router and this Mac aren't for that.
    private func hostRow(_ host: NetworkHost) -> some View {
        let settable = !host.isGateway && !host.isThisMac
        return DeskChip(help: HomeNetwork.facts(host), action: settable ? { store.setUpDevice(HomeNetwork.device(for: host)) } : nil) {
            Image(systemName: host.isGateway ? "wifi.router" : "network").frame(width: 18)
            Text(HomeNetwork.label(host)).lineLimit(1).truncationMode(.tail)
        }
        .foregroundStyle(Paper.muted)
    }

    /// A device Lamp set up itself, on the network: the ones Reconnect and Forget are for. A phone's pairing is the
    /// Mac's, and an Android device's is the device's own.
    static func keptByLamp(_ device: Device) -> Bool {
        if AndroidTVs.isRecord(device.id) { return true }
        return device.kind.isTV ? TVs.kept().contains { $0.id == device.id } : device.kind == .other && Integrations.kept(device.id) != nil
    }

    /// Whether a device's right-click offers Set Up…: one not set up with Lamp, or part-way, that Lamp can take further
    /// from here (`DeviceNextStep.takeFurther`). A device only found, even one an app can already control, is set up
    /// this way rather than told its first step: that's for the setup it opens.
    static func offersSetUp(_ device: Device, team: String) -> Bool {
        guard device.id != Device.macID, !device.isAway else { return false }
        if device.kind.isTV || device.kind == .other { return !device.isSetUp || { if case .needs = device.setup(team: team) { true } else { false } }() }
        return device.kind.isPhone && (!device.paired || !device.developerMode)
    }

    /// Reconnect: a TV's setup window, checked again from where it stands; another device's setup from the start, its
    /// certificate let go, so a reset device or one whose developer mode was turned on again is trusted afresh.
    private func reconnect(_ device: Device) {
        if AndroidTVs.isRecord(device.id) {
            AndroidWiFi.shared.show(host: device.address)
        } else if device.kind.isTV {
            TVs.reconnect(device.id)
            store.refreshDevices()
            TVSetup.shared.show(device.udid)
        } else {
            DeviceSetupModel.for(device).reconnect()
            DeviceSetupWindow.show(device)
        }
    }

    private func forget(_ device: Device) {
        if AndroidTVs.isRecord(device.id) {
            AndroidTVs.forget(device.id)
        } else if device.kind.isTV {
            TVs.forget(device.id)
        } else {
            DeviceSetupModel.discard(device.id)
            Integrations.forget(device.id)
        }
        forgetting = nil
        store.refreshDevices()
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
        return DeskChip(help: name, tip: tip(device, name: name, state: state), action: state == .here || state == .away ? nil : { act(device, state: state) }) {
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
        .contextMenu {
            if Self.offersSetUp(device, team: team) {
                Button("Set Up…") { _ = DeviceNextStep.takeFurther(device, store: store) }
            }
            if Self.keptByLamp(device) {
                Button("Reconnect…") { reconnect(device) }
                Button("Forget \(device.name)…") { forgetting = device }
            }
        }
        .accessibilityValue(state == .setUp ? "Not set up" : state == .away ? "Not on this network" : state == .found ? "Found on your network" : "Ready")
    }

    /// What's known of a device, for its tip: what it is, what it's called at home, where it is, where its setup
    /// stands and what a click does. Never its address: that's for a host's own tip and the agent.
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
        // An app on a phone signed with a free account stops opening after a week: said where the phone is.
        let stopped = store.projects.filter { PhoneRenewals.stoppedOpening($0, on: device.udid) }.map(\.name)
        if !stopped.isEmpty { lines.append("\(TeamLimits.list(stopped)) stopped opening. Open \(stopped.count == 1 ? "it" : "each") and press Play.") }
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
            return DeviceTip(title: name, lines: lines, status: ("Not on this network just now", .secondary), hint: nil)
        }
    }

    private func act(_ device: Device, state: Standing) {
        switch state {
        case .here: break
        case .ready: wishFor(Self.words(for: device))
        case .found: wishFor(Self.label(device))
        case .setUp: _ = DeviceNextStep.takeFurther(device, store: store)
        case .away: break
        }
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
