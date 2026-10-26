import Combine
import AppKit
import SwiftUI

/// Connecting an Android device over Wi‑Fi: the only way to reach most TVs (a Google TV, an Android TV, a Fire TV),
/// which have no cable to plug into a Mac, and handy for a phone. adb does it: a device of Android 11 or later pairs
/// with a code it shows (`adb pair`) and then connects; an older one, and a Fire TV, connects on port 5555 once its
/// network debugging is on, and asks on its screen whether to allow this Mac. Once connected, adb lists it like a
/// device on a cable (`Adb.devices`), and Try On offers it.
@MainActor
final class AndroidWiFi: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = AndroidWiFi()

    /// A device on the network that's offering to pair or to connect, as adb's own search finds it.
    struct Found: Identifiable, Equatable {
        var id: String { host }
        let host: String
        var pairPort: Int?
        var connectPort: Int?
    }

    enum State: Equatable { case idle, working(String), done(String), failed(String) }

    @Published private(set) var found: [Found] = []
    @Published var address = ""
    @Published var code = ""
    @Published private(set) var state: State = .idle

    private var window: NSWindow?
    private var resizing: AnyCancellable?
    private var looking: Task<Void, Never>?

    func show() {
        if window == nil {
            let (window, resizing) = FittedWindow.make(AndroidWiFiView(model: self), following: objectWillChange)
            self.resizing = resizing
            window.delegate = self
            window.title = "Connect Over Wi‑Fi"
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // What's offering to pair changes as the person opens and closes its screen on the TV.
        looking?.cancel()
        looking = Task { [weak self] in
            while !Task.isCancelled {
                let services = await Adb.networkServices()
                guard let self else { return }
                self.found = services
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        looking?.cancel()
        looking = nil
        window = nil
        state = .idle
        code = ""
    }

    func choose(_ device: Found) {
        address = device.host
    }

    /// Pairs with the code when there is one, then connects; without one, connects to where the device listens.
    func connect() {
        let typed = address.trimmed
        let parts = typed.split(separator: ":", maxSplits: 1).map(String.init)
        guard let host = parts.first, DeviceAddress.isPrivate(host) else {
            state = .failed("Type the address the TV shows, like 192.168.1.20, on this Mac's network.")
            return
        }
        let port = parts.count == 2 ? Int(parts[1]) : nil
        let pairing = code.trimmed
        state = .working(pairing.isEmpty ? "Connecting…" : "Pairing…")
        Task {
            var service = found.first { $0.host == host }
            if !pairing.isEmpty {
                guard let pairPort = port ?? service?.pairPort else {
                    state = .failed("Lamp can't see that device offering to pair. On it, open Wireless debugging, then Pair device with pairing code, and keep that screen open.")
                    return
                }
                if let problem = await Adb.pair(host: host, port: pairPort, code: pairing) { state = .failed(problem); return }
                code = ""
                state = .working("Connecting…")
                // A paired device offers its connection on a port of its own, which adb's search finds a moment later.
                for _ in 0..<5 where service?.connectPort == nil {
                    try? await Task.sleep(for: .seconds(1))
                    service = await Adb.networkServices().first { $0.host == host }
                }
            }
            let connectPort = pairing.isEmpty ? (port ?? service?.connectPort ?? 5555) : (service?.connectPort ?? 5555)
            if let problem = await Adb.connect(host: host, port: connectPort) { state = .failed(problem); return }
            Store.shared.refreshDevices()
            let listed = await Adb.devices().first { $0.udid.hasPrefix(host + ":") }
            if listed?.adbState == "unauthorized" {
                state = .done("Connected. On the TV, choose Allow when it asks about debugging, then choose it under Try On.")
            } else {
                state = .done("Connected to \(listed?.name ?? host). Choose it under Try On.")
            }
        }
    }
}

struct AndroidWiFiView: View {
    @ObservedObject var model: AndroidWiFi

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Google TV or Android TV: Settings, System, Developer options, Wireless debugging, then Pair device with pairing code.")
                Text("Fire TV: Settings, My Fire TV, Developer options, then ADB debugging. Leave the code empty.")
                Text("No Developer options? Under About, select the build or the device's name seven times.").foregroundStyle(.secondary)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            if !model.found.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.found) { device in
                        Button {
                            model.choose(device)
                        } label: {
                            Label(device.pairPort != nil ? "\(device.host), ready to pair" : device.host, systemImage: "tv")
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            Form {
                TextField("Address", text: $model.address, prompt: Text("192.168.1.20"))
                SecureField("Pairing code", text: $model.code, prompt: Text("Shown on the TV"))
            }
            HStack {
                switch model.state {
                case .idle: EmptyView()
                case .working(let words): ProgressView().controlSize(.small); Text(words).foregroundStyle(.secondary)
                case .done(let words): Label(words, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let words): Label(words, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                }
                Spacer()
                Button(model.code.trimmed.isEmpty ? "Connect" : "Pair and Connect") { model.connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.address.trimmed.isEmpty || { if case .working = model.state { return true } else { return false } }())
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 440)
    }
}

extension Adb {
    /// The devices on the network offering to pair or to connect, from adb's own search (Android 11 and later's
    /// wireless debugging), one per address.
    static func networkServices() async -> [AndroidWiFi.Found] {
        guard FileManager.default.isExecutableFile(atPath: AndroidTools.adb) else { return [] }
        var byHost: [String: AndroidWiFi.Found] = [:]
        // Lines like "adb-1234-abcd  _adb-tls-pairing._tcp  192.168.1.20:37123".
        for line in (await run(["mdns", "services"], timeout: 10)).output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 3, let colon = fields[2].lastIndex(of: ":"), let port = Int(fields[2][fields[2].index(after: colon)...]) else { continue }
            let host = String(fields[2][..<colon])
            guard DeviceAddress.isPrivate(host) else { continue }
            var entry = byHost[host] ?? AndroidWiFi.Found(host: host)
            if fields[1].hasPrefix("_adb-tls-pairing") { entry.pairPort = port } else if fields[1].hasPrefix("_adb-tls-connect") { entry.connectPort = port }
            byHost[host] = entry
        }
        return byHost.values.sorted { $0.host < $1.host }
    }

    /// Pairs this Mac's adb with a device by the code it shows, given on adb's input rather than in its arguments.
    /// Nil when it worked; else what went wrong, in the person's words.
    static func pair(host: String, port: Int, code: String) async -> String? {
        let result = await Subprocess.run(AndroidTools.adb, ["pair", "\(host):\(port)"], env: AndroidTools.environment, timeout: 30, input: Data((code + "\n").utf8))
        let said = (result.output + result.errors).lowercased()
        if said.contains("successfully paired") { return nil }
        if said.contains("wrong password") || said.contains("protocol fault") { return "That code didn't work. Check the code on the TV and try again." }
        return "The TV didn't pair. Keep its pairing screen open and try again."
    }

    /// Connects this Mac's adb to a device listening on the network. Nil when it worked or it already was.
    static func connect(host: String, port: Int) async -> String? {
        let said = (await run(["connect", "\(host):\(port)"], timeout: 20)).output.lowercased()
        if said.contains("connected to") { return nil }
        return port == 5555
            ? "The TV didn't answer. Check its network debugging (ADB debugging on a Fire TV) is on and it's on this Wi‑Fi."
            : "The TV didn't answer. Check Wireless debugging is still on and it's on this Wi‑Fi."
    }
}
