import SwiftUI
import AppKit

/// What a fresh Mac is missing before Forge can build apps.
struct SetupCheck {
    var checked = false
    var hasBuildTools = true
    var hasClaude = true
    var hasKey = true
    var installingClaude = false

    /// Developers who already use Claude Code can skip the key.
    static var useClaudeLogin: Bool {
        get { UserDefaults.standard.bool(forKey: "useClaudeLogin") }
        set { UserDefaults.standard.set(newValue, forKey: "useClaudeLogin") }
    }

    var ready: Bool { hasBuildTools && hasClaude && (hasKey || Self.useClaudeLogin) }

    static let claudePaths = ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        .map { ($0 as NSString).expandingTildeInPath }

    static func run() async -> SetupCheck {
        // `xcrun --find swift` fails (without prompting) when the Command Line Tools aren't installed.
        let tools = await Shell.run("xcrun --find swift", cwd: URL(fileURLWithPath: NSHomeDirectory())) { _ in }
        return SetupCheck(
            checked: true,
            hasBuildTools: tools == 0,
            hasClaude: claudePaths.contains { FileManager.default.isExecutableFile(atPath: $0) },
            hasKey: Keychain.openRouterKey != nil
        )
    }

    /// Opens Apple's own installer dialog for the free Command Line Tools (no developer account needed).
    static func installBuildTools() {
        Task { _ = await Shell.run("xcode-select --install", cwd: URL(fileURLWithPath: NSHomeDirectory())) { _ in } }
    }

    /// Installs Claude Code (the agent Forge drives) quietly in the background.
    static func installClaude() async -> Bool {
        await Shell.run("curl -fsSL https://claude.ai/install.sh | bash",
                        cwd: URL(fileURLWithPath: NSHomeDirectory())) { _ in } == 0
    }
}

struct SetupView: View {
    @EnvironmentObject private var store: Store
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Welcome to Forge").font(.largeTitle.bold())
            Text("A couple of one-time steps and you're ready to build apps.")
                .foregroundStyle(.secondary)

            step(done: store.setup.hasBuildTools,
                 title: "Install Apple's app-building tools",
                 detail: "macOS will show an install window. It's free, takes a few minutes, and needs no developer account.") {
                Button("Install…", action: SetupCheck.installBuildTools)
            }

            step(done: store.setup.hasClaude,
                 title: "Install the AI builder",
                 detail: store.setup.installingClaude ? "Installing…" : "Downloads automatically.") {
                if store.setup.installingClaude { ProgressView().controlSize(.small) }
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

            HStack {
                Button("Check Again") { Task { await store.recheckSetup() } }
                Spacer()
                if !store.setup.hasKey {
                    Button("I already use Claude Code") {
                        SetupCheck.useClaudeLogin = true
                        Task { await store.recheckSetup() }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: 560)
    }

    private func saveKey() {
        Keychain.setOpenRouterKey(key)
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
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !done { accessory() }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @AppStorage("model") private var model = "sonnet"
    @AppStorage("appModel") private var appModel = "haiku"
    @State private var key = ""
    @State private var hasKey = Keychain.openRouterKey != nil

    var body: some View {
        Form {
            Section("OpenRouter") {
                if hasKey {
                    LabeledContent("API key", value: "Saved in Keychain")
                    Button("Remove Key", role: .destructive) {
                        Keychain.setOpenRouterKey(nil)
                        hasKey = false
                        Task { await store.recheckSetup() }
                    }
                } else {
                    SecureField("API key", text: $key, prompt: Text("sk-or-…"))
                    Button("Save") {
                        Keychain.setOpenRouterKey(key)
                        key = ""
                        hasKey = Keychain.openRouterKey != nil
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
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
