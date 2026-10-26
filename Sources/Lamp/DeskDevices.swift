import SwiftUI
import AppKit

/// Your Devices, at the desk's end: the person's TVs, consoles, phones and whatever else answered on their network,
/// and wishes made for them. Lamp looks on the network only once the person asks here (Look, `Store.lookOnNetwork`),
/// after one line saying that macOS will ask: the system's question about Local Network is asked once, and a no stays
/// until System Settings is changed, so it comes with Lamp's reason in front of it, never in the middle of a first wish.
/// From then on the tile shows what was found, and its list has wishes the model thought of for all of it together
/// (`DeviceIdeas`), each put in the bar for the person to make their own, then each device with what it still needs.
/// A Local Network turned down is said there, with where to allow it.
struct DeskDevices: View {
    @EnvironmentObject private var store: Store
    /// Puts the start of a wish in the desk's bar.
    let choose: (String) -> Void
    @State private var hovered = false
    @State private var listing = false
    @ObservedObject private var ideas = DeviceIdeas.shared
    /// The rows' height, measured: the list is as tall as they are, up to `tallest`, past which they scroll.
    @State private var rowsHeight: CGFloat = 0
    private static let tallest: CGFloat = 380

    /// What the person might make something for: not this Mac (the desk is on it), an emulator or a watch on its own.
    private var devices: [Device] {
        store.devices.filter { ![.mac, .androidEmulator, .watch].contains($0.kind) }
    }

    var body: some View {
        VStack(spacing: 6) {
            tile
                .scaleEffect(hovered ? 1.06 : 1)
                .offset(y: hovered ? -2 : 0)
            Text("Your Devices")
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 4)
        .background(Color.primary.opacity(hovered ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { show() }
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Your Devices")
        .accessibilityValue(store.looksOnNetwork ? "\(devices.count) found" : "")
        .accessibilityAction { show() }
        .focusable(interactions: .activate)
        .onKeyPress(.return) { show(); return .handled }
        .help(store.looksOnNetwork ? "Make something for your TV, console or phone" : "Find your TV, console and phones on this network")
        .popover(isPresented: $listing, arrowEdge: .trailing) { list.environment(\.colorScheme, Self.macScheme) }
        // Wishes for what's found are thought of while the list is open, once for each set of devices.
        .onChange(of: listing ? devices.map(\.id) : []) { if listing && store.looksOnNetwork { ideas.think(about: devices) } }
        .onChange(of: listing) { if listing && store.looksOnNetwork { ideas.think(about: devices) } }
    }

    /// Before the first look the list asks first (Look); after it, opening the list looks again.
    private func show() {
        if store.looksOnNetwork { store.lookForDevicesForWish() }
        listing = true
    }

    /// The Mac's own appearance, which the popover's material is drawn in.
    private static var macScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    /// Up to four of what was found, two by two, in a dashed outline the size of a wish's icon; before anything is found,
    /// a TV, a controller, a phone and an ellipsis for the rest.
    private var tile: some View {
        let symbols = store.looksOnNetwork && !devices.isEmpty ? Array(devices.prefix(4).map(Self.symbol)) : ["tv", "gamecontroller", "iphone", "ellipsis"]
        return RoundedRectangle(cornerRadius: 17, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            .frame(width: 76, height: 76)
            .overlay {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(Array(stride(from: 0, to: symbols.count, by: 2)), id: \.self) { row in
                        GridRow {
                            ForEach(row..<min(row + 2, symbols.count), id: \.self) { index in
                                symbol(symbols[index], size: symbols.count > 2 ? 17 : 22)
                            }
                        }
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if store.localNetworkDenied {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, .orange)
                        .background(Circle().fill(.background).padding(-2))
                        .offset(x: 7, y: -7)
                }
            }
    }

    private func symbol(_ name: String, size: CGFloat = 17) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
    }

    @ViewBuilder private var list: some View {
        if store.looksOnNetwork { found } else { ask }
    }

    /// What the person accepts before the first look: macOS's question, which comes once.
    private var ask: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your Devices").font(.headline)
            Text("Lamp looks on this network for your TVs, consoles and phones. macOS will ask you to allow it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            HStack {
                Spacer()
                Button("Look") { store.lookOnNetwork() }.keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
        .padding(18)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var found: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your Devices").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if ideas.thinking && ideas.ideas.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Thinking of wishes…").foregroundStyle(.secondary)
                            }
                        }
                        ForEach(ideas.ideas) { idea($0) }
                        if !ideas.ideas.isEmpty {
                            Button(ideas.thinking ? "Thinking…" : "Other Ideas") { ideas.think(about: devices, again: true) }
                                .controlSize(.small).disabled(ideas.thinking)
                            Divider()
                        }
                        ForEach(devices) { row($0) }
                    }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                }
                .frame(height: min(rowsHeight, Self.tallest))
                .scrollBounceBehavior(.basedOnSize)
                if store.localNetworkDenied {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).frame(width: 20)
                        Text("Lamp can't look on this network.").foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Button("Allow…") { NSWorkspace.shared.open(LocalNetwork.settingsURL) }.controlSize(.small)
                    }
                    .help("Turn on Lamp in System Settings → Privacy & Security → Local Network")
                }
                HStack {
                    if store.lookingForDevices {
                        LookingForDevices()
                    } else if devices.isEmpty && !store.localNetworkDenied {
                        Text("No TVs, consoles or phones found.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Look Again") { store.refreshDevices() }.controlSize(.small).disabled(store.lookingForDevices)
                }
            }
            .padding(.top, 14)
        }
        .padding(18)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A wish the model thought of, which goes in the bar to be made the person's own.
    private func idea(_ idea: DeviceIdeas.Idea) -> some View {
        Button { listing = false; choose(idea.wish) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(idea.wish).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if !idea.devices.isEmpty {
                        Text(idea.devices.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Put this wish in the bar")
    }

    private func row(_ device: Device) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: Self.symbol(device)).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).lineLimit(1)
                if !device.line.isEmpty { Text(device.line).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 12)
            // What a device still needs, where Lamp can take it there; one that's ready shows nothing.
            if device.setup() != .ready { DeviceNextStep(device: device, then: { listing = false }) }
        }
        .accessibilityElement(children: .contain)
    }

    /// A console by its integration's kind, every other device by its own.
    static func symbol(_ device: Device) -> String {
        if device.kind == .other, let integration = device.integration.flatMap(Integrations.integration) {
            switch integration.kind {
            case "game console": return "gamecontroller"
            case "streaming player": return "tv.and.mediabox"
            case "speaker": return "hifispeaker"
            default: return device.kind.symbol
            }
        }
        return device.kind.symbol
    }
}
