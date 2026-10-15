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
    static var helper: URL { BrowserBridge.folder.appendingPathComponent("BrowserNativeHost") }
    static var bundledHelper: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BrowserNativeHost") }
    static var extensionID: String { (try? String(contentsOf: source.appendingPathComponent("extension-id.txt")))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    /// Where each piece of the connection lives: this Lamp's own, or a test's.
    @MainActor struct Layout {
        var hostManifest: URL
        var helper: URL
        var bundledHelper: URL
        var bundledExtension: URL
        var extensionFolder: URL
        var config: URL
        var secret: URL
        var extensionID: String
        var port: Int

        static var current: Layout {
            Layout(hostManifest: BrowserSetup.hostManifest, helper: BrowserSetup.helper, bundledHelper: BrowserSetup.bundledHelper,
                   bundledExtension: BrowserSetup.source.appendingPathComponent("extension"), extensionFolder: BrowserSetup.extensionFolder,
                   config: BrowserBridge.folder.appendingPathComponent("config.json"), secret: BrowserBridge.secretURL,
                   extensionID: BrowserSetup.extensionID, port: Int(Edition.gatewayPort))
        }
        /// What Chrome's manifest says when this Lamp wrote it: Chrome starts this helper, for this extension only.
        var manifestIsOurs: Bool {
            guard !extensionID.isEmpty, let data = try? Data(contentsOf: hostManifest),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return manifest["name"] as? String == BrowserSetup.hostName && manifest["path"] as? String == helper.path
                && manifest["type"] as? String == "stdio" && manifest["allowed_origins"] as? [String] == ["chrome-extension://\(extensionID)/"]
        }
        var extensionMatches: Bool {
            guard let expected = BrowserSetup.files(in: bundledExtension), !expected.isEmpty else { return false }
            return BrowserSetup.files(in: extensionFolder) == expected
        }
        var configData: Data? { try? JSONSerialization.data(withJSONObject: ["port": port, "secretPath": secret.path], options: [.sortedKeys]) }
        var configMatches: Bool {
            guard let data = try? Data(contentsOf: config), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return value["port"] as? Int == port && value["secretPath"] as? String == secret.path
        }
        var helperMatches: Bool {
            guard let installed = try? Data(contentsOf: helper), let bundled = try? Data(contentsOf: bundledHelper) else { return false }
            return installed == bundled && FileManager.default.isExecutableFile(atPath: helper.path)
        }
    }

    init() {
        refresh()
        if Edition.isDev {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }
    /// Whether the extension has answered since this connection was installed. Kept, so Chrome being closed
    /// doesn't make Lamp offer the setup again: it's set up, and works when Chrome next opens.
    private static let heardKey = "browserCompanionHeard"
    func receiveHello(version: Int) {
        guard version == 3 else { return }
        heard = Date()
        UserDefaults.standard.set(true, forKey: Self.heardKey)
        refresh()
    }
    func refresh() {
        let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil
        if BrowserBridge.enabled, Self.Layout.current.manifestIsOurs {
            try? BrowserBridge.shared.prepare()   // the secret, written back if it went missing
            Self.bringUpToDate()
        }
        let installed = Self.validBridge()
        let live = BrowserBridge.enabled && installed
            && (Date().timeIntervalSince(heard) < 15 || UserDefaults.standard.bool(forKey: Self.heardKey))
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
    static var extensionMatches: Bool { Layout.current.extensionMatches }

    /// Everything Chrome needs is in place and is this Lamp's: the manifest naming its helper for its extension, the
    /// extension's files, the helper byte for byte as this Lamp ships it, its settings and the shared secret.
    static func validBridge() -> Bool { validBridge(.current) }
    static func validBridge(_ layout: Layout) -> Bool {
        guard layout.extensionMatches, layout.manifestIsOurs, layout.helperMatches, layout.configMatches,
              let secret = try? Data(contentsOf: layout.secret), !secret.isEmpty else { return false }
        return true
    }

    /// Once the person has connected Chrome, Lamp keeps its own copy of the helper and its settings current by itself:
    /// every build of Lamp brings a newly signed helper, and asking for the setup again for that would be asking the
    /// person to do Lamp's job. Only when the manifest is the one this Lamp wrote (so Chrome starts the helper in this
    /// Lamp's folder) and the extension's files are this Lamp's, since a changed extension needs Chrome to load it again.
    /// What's written is the helper this Lamp ships, so Chrome still only ever runs that. True when anything changed.
    @discardableResult
    static func bringUpToDate() -> Bool { bringUpToDate(.current) }
    @discardableResult
    static func bringUpToDate(_ layout: Layout) -> Bool {
        guard layout.manifestIsOurs, layout.extensionMatches else { return false }
        let fm = FileManager.default
        var changed = false
        if !layout.helperMatches, let bytes = try? Data(contentsOf: layout.bundledHelper) {
            guard (try? bytes.write(to: layout.helper, options: .atomic)) != nil,
                  (try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: layout.helper.path)) != nil else { return false }
            changed = true
        }
        if !layout.configMatches, let data = layout.configData {
            guard (try? data.write(to: layout.config, options: .atomic)) != nil else { return changed }
            changed = true
        }
        return changed
    }

    func install() {
        do {
            guard BrowserBridge.enabled, Self.extensionID.count == 32 else { throw Failure() }
            let fm = FileManager.default
            // New extension files have to be loaded in Chrome again, so the setup counts only once it answers.
            // A new helper alone (every build of Lamp has one) needs nothing from the person.
            if !Self.extensionMatches { UserDefaults.standard.set(false, forKey: Self.heardKey) }
            try BrowserBridge.shared.prepare()
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
            if let config = Layout.current.configData { try config.write(to: Layout.current.config, options: .atomic) }
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
                Text("Click Lamp in Chrome’s toolbar to open an app beside the page.")
                HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            } else if !browser.hasChrome {
                Text("Install Chrome to use your apps beside web pages.").foregroundStyle(.secondary)
                Button("Get Chrome…") { NSWorkspace.shared.open(URL(string: "https://www.google.com/chrome/")!) }
            } else if !browser.bridgeInstalled {
                Text("Connect Lamp to Chrome so your apps can open beside the pages you visit.").foregroundStyle(.secondary)
                Button("Install Connection") { browser.install() }.keyboardShortcut(.defaultAction)
            } else {
                Text("Until Lamp is in the Chrome Web Store, its extension is added in Chrome’s developer mode.").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Open Chrome’s extensions and turn on Developer mode.")
                    Button("Open Chrome Extensions") { browser.openExtensions() }
                    Text("2. If Lamp is already listed, click its Reload button. Otherwise click Load unpacked and choose the Lamp extension folder.")
                    Button("Show Extension Folder") { browser.chooseFolder() }
                    Text("The folder’s location is copied too: in the chooser, press ⇧⌘G, then ⌘V and Return.").font(.caption).foregroundStyle(.secondary)
                    Text("3. Pin Lamp in Chrome’s toolbar. This window says when it’s connected.")
                }
                Button("Repair Connection") { browser.install() }.controlSize(.small)
            }
            if let problem = browser.problem { Text(problem).foregroundStyle(.red) }
            if !browser.connected { HStack { Spacer(); Button("Close") { dismiss() } } }
        }
        // Wrapped, not cut off: the steps are long sentences in a fixed-width sheet.
        .fixedSize(horizontal: false, vertical: true)
        .padding(24).frame(width: 480)
    }
}
