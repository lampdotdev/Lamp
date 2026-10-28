import SwiftUI

/// The person's devices on the desk, between the wishes and the bar, since a wish for the TV or the phone is one Lamp
/// is made for and Settings is no place to find that out. Until Lamp has looked on the network it's an invitation to,
/// whose button is the look that has macOS ask about the local network; from then on the desk looks each time it's
/// shown, and the shelf is the devices Lamp makes apps for, the likeliest first, as many as two lines hold. A ready one puts
/// itself in the bar; one that isn't takes its next step; the rest of the network is in Settings → Your Devices.
struct DeskDevices: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Store.localNetworkAskedKey) private var asked = false
    @AppStorage("appleTeam") private var team = ""
    @AppStorage("settingsTab") private var settingsTab = "building"
    @Environment(\.openSettings) private var openSettings
    @State private var adding = false
    /// Each chip's width as it's drawn, by `measured`'s keys, and the shelf's: what decides how many devices fit.
    @State private var widths: [String: CGFloat] = [:]
    @State private var room: CGFloat = 0
    /// Puts "for my <device>" in the wish bar.
    let wishFor: (String) -> Void

    /// The lines the shelf may take on the desk.
    static let lines = 2
    static let spacing: CGFloat = 8

    var body: some View {
        Group {
            if asked { shelf } else { invitation }
        }
        .sheet(isPresented: $adding) { AddDeviceSheet() }
    }

    private var invitation: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                ForEach(["iphone", "ipad", "tv", "gamecontroller", "hifispeaker", "applewatch"], id: \.self) {
                    Image(systemName: $0)
                }
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            Text("Make apps for your phone, TV and more")
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary.opacity(0.8))
            if store.lookingForDevices {
                LookingForDevices()
            } else {
                Button("Find My Devices") { store.refreshDevices() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(.leading, 22).padding(.trailing, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.72), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }

    private var shelf: some View {
        let list = HomeNetwork.List(devices: [store.thisMac].compactMap { $0 } + store.devices, hosts: store.hosts)
        let ranked = Self.ranked(list, team: team)
        let shown = Self.fitting(ranked.map { widths[Self.key($0)] ?? 0 }, more: widths["more"] ?? 0, add: widths["add"] ?? 0,
                                 learnable: list.couldLearn.count, room: room)
        let more = ranked.count - shown + list.couldLearn.count
        return VStack(spacing: 10) {
            DeskFlow(spacing: Self.spacing, lineSpacing: Self.spacing) {
                ForEach(ranked.prefix(shown)) { device in
                    chip(device)
                }
                if more > 0 { moreChip(more) }
                addChip
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { room = $0 }
            if store.localNetworkRefused, !store.lookingForDevices { LocalNetworkRefused() }
        }
        // Every chip drawn out of sight at its own width, so the shelf knows how many fit before it shows them.
        .background {
            ZStack {
                ForEach(ranked) { device in measured(Self.key(device)) { chip(device) } }
                measured("more") { moreChip(ranked.count + list.couldLearn.count) }
                measured("add") { addChip }
            }
            .frame(width: 0, height: 0)
            .hidden()
            .accessibilityHidden(true)
        }
        .animation(.easeOut(duration: 0.25), value: ranked.prefix(shown).map(\.id))
    }

    private static func key(_ device: Device) -> String { "device:" + device.id }

    private func measured(_ key: String, @ViewBuilder _ chip: () -> some View) -> some View {
        chip().fixedSize().onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { widths[key] = $0 }
    }

    private func moreChip(_ count: Int) -> some View {
        DeskChip(help: "All your devices, in Settings", action: showAll) {
            Text("\(count) More").foregroundStyle(.secondary)
        }
    }

    private var addChip: some View {
        DeskChip(help: "Plug in a phone or tablet, or set up another device", action: { adding = true }) {
            // While Lamp looks, the plus turns, so the shelf doesn't move for it.
            if store.lookingForDevices {
                ProgressView().controlSize(.small).frame(width: 16, height: 16).help("Looking for devices…")
            } else {
                Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 16, height: 16)
            }
            Text("Add a Device")
        }
    }

    /// How many of the ranked devices the shelf shows: as many as fit in its lines with More after them (when any is
    /// left out, or there's something Lamp could only learn) and Add a Device last, which are always there. Before the
    /// shelf knows its width, all of them.
    static func fitting(_ devices: [CGFloat], more: CGFloat, add: CGFloat, learnable: Int, room: CGFloat) -> Int {
        guard room > 0 else { return devices.count }
        for left in 0...devices.count {
            var chips = Array(devices.prefix(devices.count - left))
            if left + learnable > 0 { chips.append(more) }
            chips.append(add)
            if DeskFlow.lines(chips, width: room, spacing: spacing).count <= lines { return devices.count - left }
        }
        return 0
    }

    enum Standing: Equatable { case here, ready, setUp, away }

    static func state(of device: Device, team: String) -> Standing {
        if device.id == Device.macID { return .here }
        if device.isAway { return .away }
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

    private func chip(_ device: Device) -> some View {
        let state = Self.state(of: device, team: team)
        let name = state == .here ? "This Mac" : Self.label(device)
        return DeskChip(help: name, tip: tip(device, name: name, state: state), action: state == .here ? nil : { act(device, state: state) }) {
            Image(systemName: device.symbol).foregroundStyle(.secondary)
            Text(name).lineLimit(1).truncationMode(.tail).frame(maxWidth: 200)
            switch state {
            case .here, .ready:
                DeviceDot(color: .green)
            case .setUp:
                Image(systemName: "gearshape").foregroundStyle(.secondary)
                DeviceDot(color: DeviceDot.amber)
            case .away:
                EmptyView()
            }
        }
        .opacity(state == .away ? 0.5 : 1)
        .accessibilityValue(state == .setUp ? "Not set up" : state == .away ? "Not on this network" : "Ready")
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
        case .away:
            return DeviceTip(title: name, lines: lines, status: ("Not on this network just now", .secondary), hint: "Click to see all your devices.")
        }
    }

    private func act(_ device: Device, state: Standing) {
        switch state {
        case .here: break
        case .ready: wishFor(Self.words(for: device))
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

/// One of the shelf's capsules, lit under the pointer as the desk's ideas button is. One with no action is only shown.
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
        let label = HStack(spacing: 7) { content }
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Color.white.opacity(lit ? 0.95 : 0.72), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(lit ? 0.2 : 0.1), lineWidth: 1))
            .contentShape(Capsule())
            .onHover { hovered = $0 }
            .help(tip == nil ? help : "")
            .task(id: hovered) {
                guard hovered, tip != nil else { tipShown = false; return }
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled { tipShown = true }
            }
            .popover(isPresented: $tipShown, arrowEdge: .bottom) {
                if let tip { tip.interactiveDismissDisabled() }
            }
        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label.accessibilityElement(children: .combine)
        }
    }
}

/// Views of their own widths in rows, each row centered, wrapping where the next one doesn't fit.
struct DeskFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    /// Where widths break into lines in `width`, by index: each goes on the line it started until the next doesn't fit.
    static func lines(_ widths: [CGFloat], width: CGFloat, spacing: CGFloat) -> [[Int]] {
        var lines: [[Int]] = [[]]
        var used: CGFloat = 0
        for (index, each) in widths.enumerated() {
            if !lines[lines.count - 1].isEmpty, used + spacing + each > width {
                lines.append([])
                used = 0
            }
            used += (lines[lines.count - 1].isEmpty ? 0 : spacing) + each
            lines[lines.count - 1].append(index)
        }
        return lines
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(view: LayoutSubviews.Element, size: CGSize)]] {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return Self.lines(sizes.map(\.width), width: width, spacing: spacing).map { $0.map { (subviews[$0], sizes[$0]) } }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = rows(subviews, width: width)
        let widest = lines.map { $0.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, $0.count - 1)) }.max() ?? 0
        let heights = lines.map { $0.map(\.size.height).max() ?? 0 }
        return CGSize(width: proposal.width ?? widest, height: heights.reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in rows(subviews, width: bounds.width) {
            let used = line.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, line.count - 1))
            let tallest = line.map(\.size.height).max() ?? 0
            var x = bounds.midX - used / 2
            for item in line {
                item.view.place(at: CGPoint(x: x, y: y + (tallest - item.size.height) / 2), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += tallest + lineSpacing
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
