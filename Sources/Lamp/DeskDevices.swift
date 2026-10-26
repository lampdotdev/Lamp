import SwiftUI
import AppKit

/// Your Devices, at the desk's end: the person's TVs, consoles and phones, each with a wish to start for it. Lamp looks
/// on the network only once this is clicked the first time (`Store.lookOnNetwork`), so the system's question about
/// Local Network comes when the person asked to look, not in the middle of a first wish. From then on the tile shows
/// what was found, and its list puts the start of a wish for one in the bar ("A game for my Xbox: "), for the person to
/// finish; a device nothing in Lamp knows yet is set up from there instead. A Local Network turned down is said there,
/// with where to allow it.
struct DeskDevices: View {
    @EnvironmentObject private var store: Store
    /// Puts the start of a wish in the desk's bar.
    let choose: (String) -> Void
    @State private var hovered = false
    @State private var listing = false

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
    }

    /// The first click is the person asking Lamp to look on the network; later ones look again.
    private func show() {
        if store.looksOnNetwork { store.lookForDevicesForWish() } else { store.lookOnNetwork() }
        listing = true
    }

    /// The Mac's own appearance, which the popover's material is drawn in.
    private static var macScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    /// Up to four of what was found, two by two, in a dashed outline the size of a wish's icon; before the first look,
    /// a TV and a controller.
    private var tile: some View {
        let symbols = store.looksOnNetwork && !devices.isEmpty ? Array(devices.prefix(4).map(Self.symbol)) : ["tv", "gamecontroller"]
        return RoundedRectangle(cornerRadius: 17, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            .frame(width: 76, height: 76)
            .overlay {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(Array(stride(from: 0, to: symbols.count, by: 2)), id: \.self) { row in
                        GridRow {
                            ForEach(row..<min(row + 2, symbols.count), id: \.self) { index in
                                Image(systemName: symbols[index])
                                    .font(.system(size: symbols.count > 2 ? 17 : 22, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
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

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your Devices").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(devices) { row($0) }
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

    private func row(_ device: Device) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: Self.symbol(device)).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).lineLimit(1)
                if !device.line.isEmpty { Text(device.line).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 12)
            if let start = Self.wishStart(for: device) {
                // What it still needs is asked for when a wish first goes there, as everywhere else.
                Button("Make…") { listing = false; choose(start) }
                    .controlSize(.small)
                    .accessibilityLabel("Make something for \(device.name)")
            } else {
                DeviceNextStep(device: device, then: { listing = false })
            }
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

    /// How a wish for the device starts, in the person's own words for it, so the naming call reads it as that device
    /// (`AppName.seen`); nil for one Lamp doesn't know yet, which is set up first.
    static func wishStart(for device: Device) -> String? {
        switch device.kind {
        case .iphone: return "An app for my iPhone: "
        case .ipad: return "An app for my iPad: "
        case .android: return "An app for my Android phone: "
        case .samsungTV, .lgTV: return "Something for my TV: "
        case .other:
            guard let integration = device.integration.flatMap(Integrations.integration) else { return nil }
            return integration.kind == "game console" ? "A game for my \(integration.name): " : "Something for my \(integration.name): "
        default: return nil
        }
    }
}
