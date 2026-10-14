import SwiftUI
import CryptoKit

/// Disk checks establish the local connection; only a signed round trip from Chrome proves the extension works.
@MainActor
final class BrowserSetup: ObservableObject {
    static let shared = BrowserSetup()
    @Published private(set) var bridgeInstalled = false
    @Published private(set) var connected = false
    @Published private(set) var hasChrome = false
    @Published var problem: String?
    private var heard = Date.distantPast
    private var timer: Timer?
    static let hostName = "dev.lamp.prototype"
    static let folder = Edition.supportFolder.appendingPathComponent("BrowserCompanion")
    static let extensionFolder = folder.appendingPathComponent("Extension")
    static var source: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BrowserCompanion") }
    static var hostManifest: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts/\(hostName).json")
    }
    static var helper: URL { BrowserPrototype.folder.appendingPathComponent("BrowserNativeHost") }
    static var bundledHelper: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BrowserNativeHost") }
    static var extensionID: String { (try? String(contentsOf: source.appendingPathComponent("extension-id.txt")))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    init() {
        refresh()
        if Edition.isDev {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }
    func receiveHello(version: Int) {
        guard version == 2 else { return }
        heard = Date(); refresh()
    }
    func refresh() {
        let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil
        let installed = Self.validBridge()
        let live = BrowserPrototype.enabled && installed && Date().timeIntervalSince(heard) < 15
        if hasChrome != chrome { hasChrome = chrome }
        if bridgeInstalled != installed { bridgeInstalled = installed }
        if connected != live { connected = live }
    }
    /// The unpacked extension is Lamp-owned. Compare all files so repair also restores a missing script or icon.
    static func files(in root: URL) -> [String: Data]? {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let info = try? root.resourceValues(forKeys: keys), info.isDirectory == true, info.isSymbolicLink != true,
              let entries = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { return nil }
        var result: [String: Data] = [:]
        for case let file as URL in entries {
            guard let info = try? file.resourceValues(forKeys: keys), info.isSymbolicLink != true else { return nil }
            if info.isRegularFile == true {
                guard let data = try? Data(contentsOf: file), data.count < 2_000_000 else { return nil }
                result[String(file.path.dropFirst(root.path.count + 1))] = data
            } else if info.isDirectory != true { return nil }
        }
        return result
    }
    static var extensionMatches: Bool {
        guard let expected = files(in: source.appendingPathComponent("extension")), !expected.isEmpty else { return false }
        return files(in: extensionFolder) == expected
    }
    static func validBridge() -> Bool {
        guard extensionMatches, let data = try? Data(contentsOf: hostManifest),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              manifest["name"] as? String == hostName, manifest["path"] as? String == helper.path,
              manifest["type"] as? String == "stdio", !extensionID.isEmpty,
              manifest["allowed_origins"] as? [String] == ["chrome-extension://\(extensionID)/"],
              let installed = try? Data(contentsOf: helper), let bundled = try? Data(contentsOf: bundledHelper),
              installed == bundled, FileManager.default.isExecutableFile(atPath: helper.path),
              let configData = try? Data(contentsOf: BrowserPrototype.folder.appendingPathComponent("config.json")),
              let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
              config["port"] as? Int == Int(Edition.gatewayPort),
              config["secretPath"] as? String == BrowserPrototype.folder.appendingPathComponent("secret").path,
              let secret = try? Data(contentsOf: BrowserPrototype.folder.appendingPathComponent("secret")), !secret.isEmpty else { return false }
        return true
    }
    func install() {
        do {
            guard BrowserPrototype.enabled, Self.extensionID.count == 32 else { throw Failure() }
            let fm = FileManager.default
            try BrowserPrototype.shared.prepare()
            try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let source = Self.source.appendingPathComponent("extension")
            if !Self.extensionMatches {
                let staged = Self.folder.appendingPathComponent("Extension-" + UUID().uuidString)
                try fm.copyItem(at: source, to: staged)
                defer { try? fm.removeItem(at: staged) }
                if fm.fileExists(atPath: Self.extensionFolder.path) { try fm.removeItem(at: Self.extensionFolder) }
                try fm.moveItem(at: staged, to: Self.extensionFolder)
            }
            let bytes = try Data(contentsOf: Self.bundledHelper)
            if (try? Data(contentsOf: Self.helper)) != bytes { try bytes.write(to: Self.helper, options: .atomic) }
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.helper.path)
            let config: [String: Any] = ["port": Int(Edition.gatewayPort), "secretPath": BrowserPrototype.folder.appendingPathComponent("secret").path]
            try JSONSerialization.data(withJSONObject: config).write(to: BrowserPrototype.folder.appendingPathComponent("config.json"), options: .atomic)
            try fm.createDirectory(at: Self.hostManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let manifest: [String: Any] = ["name": Self.hostName, "description": "Lamp browser companion", "path": Self.helper.path,
                                         "type": "stdio", "allowed_origins": ["chrome-extension://\(Self.extensionID)/"]]
            try JSONSerialization.data(withJSONObject: manifest).write(to: Self.hostManifest, options: .atomic)
            problem = nil
        } catch { problem = "Couldn't connect Lamp to Chrome. Try again." }
        refresh()
    }
    func openExtensions() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else { return }
        NSWorkspace.shared.open([URL(string: "chrome://extensions")!], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    func chooseFolder() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.extensionFolder.path, forType: .string)
        NSWorkspace.shared.activateFileViewerSelecting([Self.extensionFolder])
    }
    struct Failure: Error {}
}

struct BrowserSetupGuide: View {
    @ObservedObject private var browser = BrowserSetup.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Use your apps in Chrome").font(.title2.bold())
            if browser.connected {
                Label("Lamp is connected to Chrome", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Open Lamp in Chrome’s toolbar and choose Open app companion.")
                HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            } else if !browser.hasChrome {
                Text("Install Chrome to use your apps beside websites.").foregroundStyle(.secondary)
                Button("Get Chrome…") { NSWorkspace.shared.open(URL(string: "https://www.google.com/chrome/")!) }
            } else if !browser.bridgeInstalled {
                Text("Connect Lamp to Chrome so your apps can exchange what you choose in the browser.").foregroundStyle(.secondary)
                Button("Install Connection") { browser.install() }.keyboardShortcut(.defaultAction)
            } else {
                Text("This research build uses Chrome’s developer mode for its extension. Chrome will ask before a companion reads a new site.").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Open Chrome’s extensions and turn on Developer mode.")
                    Button("Open Chrome Extensions") { browser.openExtensions() }
                    Text("2. If Lamp is already listed, click its Reload button. Otherwise click Load unpacked and choose the Lamp extension folder.")
                    Button("Show Extension Folder") { browser.chooseFolder() }
                    Text("The folder’s location is copied too: in the chooser, press ⇧⌘G, then ⌘V and Return.").font(.caption).foregroundStyle(.secondary)
                    Text("3. Pin Lamp in Chrome’s toolbar. This window will confirm when it connects.")
                }
                Button("Repair Connection") { browser.install() }.controlSize(.small)
            }
            if let problem = browser.problem { Text(problem).foregroundStyle(.red) }
            if !browser.connected { HStack { Spacer(); Button("Close") { dismiss() } } }
        }.padding(24).frame(width: 480)
    }
}
