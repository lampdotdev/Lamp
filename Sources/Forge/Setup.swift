import SwiftUI
import AppKit

/// What a fresh Mac is missing before Forge can build apps.
struct SetupCheck {
    var checked = false
    var hasBuildTools = true
    var hasKey = true
    var hasAgent = true
    /// Forge has already opened Apple's installer this launch.
    var installRequested = false

    var ready: Bool { hasBuildTools && hasKey && hasAgent }

    static func run(keeping previous: SetupCheck) async -> SetupCheck {
        var check = SetupCheck(checked: true, hasBuildTools: buildToolsInstalled(), hasKey: Provider.hasKey,
                               hasAgent: Agent.executable != nil)
        check.installRequested = previous.installRequested
        return check
    }

    /// Looks for a Swift compiler without calling /usr/bin/swift or xcrun: on a Mac without the tools,
    /// those shims pop up Apple's installer, which would happen every time Forge checks.
    static func buildToolsInstalled() -> Bool {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: "/Library/Developer/CommandLineTools/usr/bin/swift") { return true }
        let select = Process()
        select.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        select.arguments = ["-p"]
        let pipe = Pipe()
        select.standardOutput = pipe
        select.standardError = FileHandle.nullDevice
        guard (try? select.run()) != nil else { return false }
        select.waitUntilExit()
        let developer = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmed ?? ""
        guard select.terminationStatus == 0, !developer.isEmpty else { return false }
        return fm.isExecutableFile(atPath: developer + "/usr/bin/swift")
            || fm.isExecutableFile(atPath: developer + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift")
    }

    /// Opens Apple's installer for the free Command Line Tools (no developer account needed).
    static func installBuildTools() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

struct SetupView: View {
    @EnvironmentObject private var store: Store
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Welcome to Forge").font(.largeTitle.bold())
            Text("Two one-time steps and you're ready to build apps. Both can happen at the same time.")
                .foregroundStyle(.secondary)

            if !store.setup.hasAgent {
                Label("Forge's AI builder is missing from the app. Download Forge again.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            step(done: store.setup.hasBuildTools,
                 title: "Install Apple's app-building tools",
                 detail: store.setup.installRequested
                    ? "Apple's installer window is open. Click **Install**, then **Agree**. It usually takes 5–10 minutes, and Forge carries on by itself when it's done."
                    : "Free from Apple, and no developer account needed.") {
                VStack(alignment: .trailing, spacing: 6) {
                    if store.setup.installRequested {
                        ProgressView().controlSize(.small)
                        Button("Show Installer Again", action: SetupCheck.installBuildTools)
                            .buttonStyle(.link)
                            .font(.caption)
                    } else {
                        Button("Install…") { store.requestBuildTools() }
                    }
                }
            }

            step(done: store.setup.hasKey,
                 title: "Add your OpenRouter key",
                 detail: "This pays for the AI. Create a key at openrouter.ai/keys and paste it here.") {
                EmptyView()
            }
            if !store.setup.hasKey {
                HStack {
                    SecureField("sk-or-…", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey).disabled(key.trimmed.isEmpty)
                    Link("Get a key", destination: URL(string: "https://openrouter.ai/keys")!)
                }
                .padding(.leading, 36)
            }
        }
        .padding(40)
        .frame(maxWidth: 560)
    }

    private func saveKey() {
        KeyStore.setOpenRouterKey(key)
        key = ""
        Task { await store.recheckSetup() }
    }

    private func step<Accessory: View>(done: Bool, title: String, detail: String,
                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(done ? .green : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(LocalizedStringKey(detail)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !done { accessory() }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @AppStorage("model") private var model = Provider.models[0].id
    @AppStorage("appModel") private var appModel = "haiku"
    @AppStorage("imageModel") private var imageModel = Icons.artModels[0].id
    @State private var key = ""
    @State private var hasKey = KeyStore.openRouterKey != nil

    var body: some View {
        Form {
            Section("OpenRouter") {
                if hasKey {
                    LabeledContent("API key", value: KeyStore.usesKeychain ? "Saved in Keychain" : "Saved")
                    Button("Remove Key", role: .destructive) {
                        KeyStore.setOpenRouterKey(nil)
                        hasKey = false
                        Task { await store.recheckSetup() }
                    }
                } else {
                    SecureField("API key", text: $key, prompt: Text("sk-or-…"))
                    Button("Save") {
                        KeyStore.setOpenRouterKey(key)
                        key = ""
                        hasKey = KeyStore.openRouterKey != nil
                        Task { await store.recheckSetup() }
                    }
                    .disabled(key.trimmed.isEmpty)
                }
                Link("Manage keys and credit on openrouter.ai", destination: URL(string: "https://openrouter.ai/keys")!)
            }
            Section("AI models") {
                Picker("Building apps", selection: $model) {
                    ForEach(Provider.models, id: \.id) { Text($0.label).tag($0.id) }
                }
                Picker("Inside your apps", selection: $appModel) {
                    ForEach(AppAI.models, id: \.id) { Text($0.label).tag($0.id) }
                }
                Picker("Images (icons and in-app)", selection: $imageModel) {
                    ForEach(Icons.artModels, id: \.id) { Text($0.label).tag($0.id) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
