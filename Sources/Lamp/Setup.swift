import SwiftUI
import AppKit
import LampSidebarKit

/// What a fresh Mac is missing before Lamp can build apps.
struct SetupCheck {
    var checked = false
    var hasBuildTools = true
    var builderProblem: String?
    var hasAgent = true
    /// Lamp has already opened Apple's installer this launch.
    var installRequested = false
    /// When it last did: an installer that never shows up soon after is treated as one that didn't finish.
    var installRequestedAt: Date?
    /// Apple's installer window is open.
    var installerOpen = false
    /// It has been open since the install was asked for, so its closing with no tools means it didn't finish.
    var installerSeen = false
    /// The person came back to Lamp while it was open: they've been through its buttons, so it's installing.
    var backFromInstaller = false

    /// Where the install of the tools has got to, for the screens that show it.
    enum InstallStage { case notAsked, inApplesWindow, installing, failed, installed }
    var installStage: InstallStage {
        if hasBuildTools { return .installed }
        if !installRequested { return .notAsked }
        if installerOpen { return backFromInstaller ? .installing : .inApplesWindow }
        // Closed again, or never opened: either way the person needs Try Again, not instructions.
        let late = installRequestedAt.map { Date().timeIntervalSince($0) > Self.installerPatience } ?? false
        return installerSeen || late ? .failed : .inApplesWindow
    }

    /// How long Apple's installer may take to appear after it's asked for.
    static let installerPatience: TimeInterval = 15

    var hasBuilder: Bool { builderProblem == nil }
    var ready: Bool { hasBuildTools && hasBuilder && hasAgent }

    static func run(keeping previous: SetupCheck) async -> SetupCheck {
        // Whether Claude Code or Codex is there depends on the look for the person's own copy, which takes a few
        // seconds at launch: judged before it's done, a Mac with one showed the setup screen until it finished.
        if Builder.engine != .pi, !EngineInstall.hasLooked { await EngineInstall.lookForPersonsCopies() }
        var check = SetupCheck(checked: true, hasBuildTools: buildToolsInstalled(), builderProblem: Builder.problem(),
                               hasAgent: Agent.executable != nil)
        check.installerOpen = installerIsOpen()
        return check.keeping(previous)
    }

    /// This look, with what the person has done since the install was asked for carried over from `current`:
    /// a click made while the look was under way counts.
    func keeping(_ current: SetupCheck) -> SetupCheck {
        var check = self
        check.installRequested = current.installRequested
        check.installRequestedAt = current.installRequestedAt
        check.installerSeen = current.installerSeen || installerOpen
        check.backFromInstaller = current.backFromInstaller || Pretend.backFromInstaller
        return check
    }

    /// Looks for a Swift compiler without calling /usr/bin/swift or xcrun: on a Mac without the tools,
    /// those shims pop up Apple's installer, which would happen every time Lamp checks.
    static func buildToolsInstalled() -> Bool {
        if Pretend.toolsMissing { return false }
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: "/Library/Developer/CommandLineTools/usr/bin/swift") { return true }
        let select = Subprocess.runBlocking("/usr/bin/xcode-select", ["-p"], mergeErrors: false, timeout: 10)
        let developer = select.output.trimmed
        guard select.ok, !developer.isEmpty else { return false }
        return fm.isExecutableFile(atPath: developer + "/usr/bin/swift")
            || fm.isExecutableFile(atPath: developer + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift")
    }

    /// The app macOS opens for `xcode-select --install`: the Command Line Tools' own installer.
    static let installerID = "com.apple.dt.CommandLineTools.installondemand"

    static func installerIsOpen() -> Bool {
        if Pretend.isMissing("tools") { return Pretend.installerOpen }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: installerID).isEmpty
    }

    /// Brings Apple's installer back to the front, or opens it again if it was closed.
    static func showInstaller() {
        if Pretend.isMissing("tools") {
            Pretend.startInstall()   // nothing to bring forward; starts the stand-in over if it has closed
            return
        }
        if let installer = NSRunningApplication.runningApplications(withBundleIdentifier: installerID).first {
            installer.activate()
        } else {
            installBuildTools()
        }
    }

    /// Opens Apple's installer for the free Command Line Tools (no developer account needed).
    static func installBuildTools() {
        if Pretend.isMissing("tools") {
            Pretend.startInstall()
            return
        }
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
    @State private var checkingKey = false
    @State private var keyProblem: String?
    @State private var choice = "openrouter"

    /// The ways to build, in the order shown. Choosing Claude Code or Codex downloads Lamp's copy
    /// when the Mac has none.
    private static var choices: [(id: String, title: String, detail: String)] {
        var all: [(id: String, title: String, detail: String)] = [
            ("openrouter", "OpenRouter",
             "Any of hundreds of models, paying OpenRouter only for what you use."),
        ]
        for engine in [Engine.claude, .codex] {
            all.append((engine.rawValue, engine.title,
                        "Uses your \(engine.title) sign-in, for building and for the AI inside your apps."))
        }
        all.append(("local", "A model on this Mac",
                    "Free and private: a model Lamp downloads and runs here. Smaller models build simpler apps."))
        return all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Lamp can't build apps right now").font(.largeTitle.bold())
            Text("Finish what's left below. Your apps and chats are kept.")
                .foregroundStyle(.secondary)

            if !store.setup.hasAgent {
                Label("Lamp's AI builder is missing from the app. Download Lamp again.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            step(done: store.setup.hasBuildTools,
                 title: "Install Apple's app-building tools",
                 detail: store.setup.installRequested
                    ? "Apple's installer window is open. Click **Install**, then **Agree**. It usually takes 5–10 minutes, and Lamp carries on by itself when it's done."
                    : "Free from Apple, and no developer account needed.") {
                VStack(alignment: .trailing, spacing: 6) {
                    if store.setup.installRequested {
                        ProgressView().controlSize(.small)
                        Button("Show Installer Again", action: SetupCheck.showInstaller)
                            .buttonStyle(.link)
                            .font(.caption)
                    } else {
                        Button("Install…") { store.requestBuildTools() }
                    }
                }
            }

            step(done: store.setup.hasBuilder,
                 title: "Choose what builds your apps",
                 detail: store.setup.hasBuilder ? Builder.summary
                    : "Any of these works. You can change it later in Settings.") {
                EmptyView()
            }
            if !store.setup.hasBuilder {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $choice) {
                        ForEach(Self.choices, id: \.id) { Text($0.title).tag($0.id) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Text(Self.choices.first { $0.id == choice }?.detail ?? "")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    switch choice {
                    case "openrouter":
                        HStack {
                            SecureField("OpenRouter key (sk-or-…)", text: $key)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(saveKey)
                                .onChange(of: key) { keyProblem = nil }
                            if checkingKey {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Save", action: saveKey).disabled(key.trimmed.isEmpty)
                            }
                            Link("Get a key", destination: URL(string: "https://openrouter.ai/keys")!)
                        }
                        if let keyProblem {
                            Label(keyProblem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                        }
                    case "claude", "codex":
                        let engine: Engine = choice == "claude" ? .claude : .codex
                        Button("Use \(engine.title)") { use(engine) }
                    default:
                        Button("Choose a Model…") { openSettings(tab: "providers", sheet: Builder.localProvider) }
                    }
                }
                .padding(.leading, 36)
            }
        }
        .padding(40)
        .frame(maxWidth: 600)
    }

    @Environment(\.openSettings) private var openSettingsAction
    @AppStorage("settingsTab") private var settingsTab = "building"
    @AppStorage("settingsSheet") private var settingsSheet = ""

    private func openSettings(tab: String, sheet: String = "") {
        settingsTab = tab
        settingsSheet = sheet
        openSettingsAction()
    }

    private func use(_ engine: Engine) {
        Builder.engine = engine
        Task {
            // Lamp's copy downloads first if the Mac has none, then the sign-in opens the browser.
            await EngineDownloads.shared.ensure(engine)
            if await EngineSignIn.isSignedIn(engine) == false { _ = await EngineSignIn.signIn(engine) }
            await store.recheckSetup()
        }
    }

    /// Checks the key with OpenRouter before saving it, so a typo shows up now rather than at the first build.
    private func saveKey() {
        let candidate = key.trimmed
        guard !candidate.isEmpty, !checkingKey else { return }
        checkingKey = true
        Task {
            defer { checkingKey = false }
            if let problem = await Self.checkOpenRouterKey(candidate) {
                keyProblem = problem
                return
            }
            KeyStore.setOpenRouterKey(candidate)
            key = ""
            Builder.engine = .pi
            Builder.piProvider = "openrouter"
            await store.recheckSetup()
        }
    }

    /// What OpenRouter said about a key.
    enum KeyVerdict: Equatable {
        case accepted
        /// OpenRouter answered, and the key is no use as it is: mistyped, revoked or out of credit.
        case refused(String)
        /// Nothing to go on (offline, or OpenRouter in trouble), so the key may well be a good one.
        case unchecked(String)

        var problem: String? {
            switch self {
            case .accepted: nil
            case .refused(let problem), .unchecked(let problem): problem
            }
        }
    }

    /// nil if OpenRouter accepts the key; otherwise what's wrong, in plain words.
    static func checkOpenRouterKey(_ key: String) async -> String? {
        await openRouterVerdict(key).problem
    }

    /// Asks OpenRouter about a key. Where the person can wait for the answer (the first key, in the Welcome
    /// and the chat) anything but `accepted` stops the save; Settings turns away only a key OpenRouter refused.
    static func openRouterVerdict(_ key: String) async -> KeyVerdict {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .unchecked("Couldn't reach OpenRouter. Check your internet connection.")
        }
        return verdict(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }

    /// What OpenRouter's answer to "whose key is this?" means for the key.
    static func verdict(status: Int, body: Data) -> KeyVerdict {
        switch status {
        case 200:
            let info = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["data"] as? [String: Any]
            if let remaining = info?["limit_remaining"] as? Double, remaining <= 0 {
                return .refused("That key works, but it has no credit left. Add credit at openrouter.ai, then try again.")
            }
            return .accepted
        case 401, 403: return .refused("OpenRouter didn't accept that key. Copy it again from openrouter.ai/keys.")
        default: return .unchecked("OpenRouter couldn't check the key right now. Try again in a moment.")
        }
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !done { accessory() }
        }
    }
}

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "building"

    var body: some View {
        TabView(selection: $tab) {
            BuildingSettings().tabItem { Label("Building", systemImage: "hammer") }.tag("building")
            AppsSettings().tabItem { Label("Apps", systemImage: "square.grid.2x2") }.tag("apps")
            ProvidersSettings().tabItem { Label("AI Providers", systemImage: "cpu") }.tag("providers")
            MemorySettings().tabItem { Label("Memory", systemImage: "note.text") }.tag("memory")
            if ExperimentalSettings.hasAny {
                ExperimentalSettings().tabItem { Label("Experimental", systemImage: "flask") }.tag("experimental")
            }
        }
        .frame(width: 560)
        .onAppear {
            if tab == "local" { tab = "providers" }   // Local Models is now Native Mac AI, under Providers
            if !(["building", "apps", "providers", "memory"] + (ExperimentalSettings.hasAny ? ["experimental"] : [])).contains(tab) { tab = "building" }
        }
    }
}

/// What's in Lamp but not yet for everyone: each switch here brings a feature into the interface. The tab is there
/// only while there is something to show: now Apps in Chrome, which only a build from source carries (the extension
/// and its helper are in Lamp Dev's bundle only).
struct ExperimentalSettings: View {
    static var hasAny: Bool { Edition.isDev }
    @AppStorage(BrowserBridge.switchKey) private var browser = ProcessInfo.processInfo.environment["LAMP_BROWSER_PROTOTYPE"] == "1"
    @AppStorage(Publish.switchKey) private var publish = false

    var body: some View {
        Form {
            Section {
                SettingsCheckboxes {
                    Toggle("Apps in Chrome", isOn: $browser)
                        .checkboxNote("Apps that help with web pages also open beside the page, in Chrome's sidebar.")
                    if browser { BrowserConnectionUpgrade(compact: true).underCheckbox() }
                    Toggle("Publish games as web pages", isOn: $publish)
                        .checkboxNote("A game's Share menu can put it on GitHub Pages, from your own GitHub account.")
                }
            } header: {
                // Above the box, in a checkbox note's size and color rather than as a heading.
                Text("Features the Lamp team is still working on. They may not be ready for prime time.")
                    .font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
            }
        }
        .settingsPane()
        .onChange(of: browser) { _, on in
            if on { try? BrowserBridge.shared.prepare() }
            BrowserSetup.shared.refresh()
        }
    }
}

extension View {
    /// A grouped settings form that grows to fit its content, so the Settings window
    /// resizes per tab like Apple's apps, and scrolls only when it's taller than the screen.
    func settingsPane() -> some View { modifier(SettingsPane()) }
}

private struct SettingsPane: ViewModifier {
    @State private var height: CGFloat = 0
    @State private var window: NSWindow?
    /// Goes up when the window moves to another screen, which has room of its own.
    @State private var screenChanges = 0

    /// Room left on the window's own screen once its title bar and toolbar are taken off, as they are, with a little
    /// to spare. A pane any taller makes a window macOS won't put on screen: it's shrunk to fit, the pane asks for its
    /// height again, and the two go on until AppKit gives up and Lamp crashes. The screen is the window's (the main
    /// one can be another size), and the chrome is measured, since a toolbar's height isn't the same everywhere.
    private var maxHeight: CGFloat {
        _ = screenChanges
        let screen = window?.screen ?? NSScreen.main
        let chrome = window.map { $0.frame.height - $0.contentLayoutRect.height } ?? 120
        return max(200, ((screen?.visibleFrame.height ?? 800) - chrome - 20).rounded(.down))
    }

    func body(content: Content) -> some View {
        ScrollView {
            content
                .formStyle(.grouped)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollDisabled(height <= maxHeight)
        .frame(height: height == 0 ? nil : min(height, maxHeight))
        .background(SettingsWindowReader { window = $0; keepOnScreen() })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { note in
            if (note.object as? NSWindow) === window { screenChanges += 1 }
        }
        // The pane's height as drawn, which a move to another screen changes too (its cap is that screen's).
        .onChange(of: min(height, maxHeight)) { keepOnScreen() }
    }

    /// The window keeps its top where it is as the pane grows, as Settings windows do, so one opened low on the
    /// screen grows past its bottom; macOS then fits it back while the pane is still asking for the height, which is
    /// the loop above. Once the window has taken its new height, it's moved up just enough to be on screen whole.
    private func keepOnScreen() {
        DispatchQueue.main.async {
            guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
            var frame = window.frame
            guard frame.minY < visible.minY else { return }
            frame.origin.y = min(visible.minY, visible.maxY - frame.height)
            window.setFrameOrigin(frame.origin)
        }
    }
}

/// Hands back the window a Settings pane is in, once it's in one.
private struct SettingsWindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { found(window) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// A section's on/off options, as checkboxes with the box first, as Finder's settings have them: in a stack,
/// so the form doesn't lay each out as a label with its switch at the far end.
struct SettingsCheckboxes<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where a choice can't be made or used as things are. The badge is the only orange: why, and the fix, go in
/// gray in the row under it.
struct NotReadyBadge: View {
    var body: some View {
        // Icon and word close together: a Label in a form row spaces them like a list item.
        HStack(spacing: 4) { Image(systemName: "exclamationmark.circle.fill"); Text("Not Ready") }
            .foregroundStyle(.orange)
    }
}

/// A setting with nothing to choose from yet, in place of its menu: Not Ready where the menu would be.
/// The row under it says why and offers the fix.
struct NotReadyRow: View {
    let title: String

    var body: some View {
        LabeledContent(title) { NotReadyBadge() }
    }
}

/// Image generation, in Building (icon artwork) and Apps (apps' pictures): the models that can make pictures
/// now, showing what's used when the saved one can't be; Codex's name when it draws with its own model; Not
/// Ready, and how to get pictures, when nothing can. Icon artwork (`forIcons`) can also be drawn by hand in
/// Image Playground, on a Mac that has it: a fix under Not Ready, and an entry in the menu from then on.
struct ImageModelRow: View {
    @Binding var selection: String
    var forIcons = false
    /// Read so the row follows the choice wherever it's made (the chat's card makes it too).
    @AppStorage("iconModel") private var saved = ""
    @AppStorage("settingsTab") private var tab = "building"

    var body: some View {
        let _ = saved
        let images = Icons.usableChoices
        // What answers is the resolver's to say: pictures by Settings' choices, and for icon artwork
        // whether the person draws it instead. The menu only lays that out.
        let pictures = AppAI.resolve(.pictures)
        let context: AIContext = forIcons ? .icon : .mac
        let resolution = forIcons ? AppAI.resolve(.pictures, in: .icon) : pictures
        let label = { (id: String) -> String in
            switch id {
            case Icons.byHand: Icons.byHandLabel
            case Icons.noChoice: pictures.answer ?? "None"
            default: images.first { $0.id == id }?.label ?? id
            }
        }
        if resolution.tier == .none {
            NotReadyRow(title: "Image generation")
            CapabilityNote(capability: .pictures, context: context)
        } else {
            switch Icons.artMenu(models: images.map(\.id), selection: selection, drawer: pictures.answer,
                                 byHandAvailable: forIcons && UpgradeView.isOffered(.drawIcons),
                                 byHandChosen: resolution.provider == Icons.byHand) {
            case .named(let id):
                // One model, or Codex drawing with its own: nothing to choose, so it's named.
                LabeledContent("Image generation", value: label(id))
            case .menu(let ids, let selected):
                Picker("Image generation", selection: Binding(get: { selected }, set: { id in
                    switch Icons.menuPick(id, forIcons: forIcons) {
                    case .providers: tab = "providers"
                    case .clear: Icons.iconChoice = nil
                    case .choose(let id): selection = id
                    }
                })) {
                    ForEach(Array(Icons.menuGroups(ids).enumerated()), id: \.offset) { _, group in
                        Section { ForEach(group, id: \.self) { id in Text(label(id)).tag(id) } }
                    }
                    Divider()
                    Text("Configure providers…").tag(Icons.configureProviders)
                }
            }
        }
    }
}

extension View {
    /// Lined up with a checkbox's words: its note, or an option that's a part of it (shown only while it's on).
    func underCheckbox() -> some View { padding(.leading, 20) }

    /// A checkbox's note, under its words. Most options need none; one that does gets a sentence or two.
    func checkboxNote(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            self
            Text(text)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .underCheckbox()
        }
    }
}

/// Which agent, provider and model build apps.
struct BuildingSettings: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var local = LocalModels.shared
    @ObservedObject private var downloads = EngineDownloads.shared
    @AppStorage("engine") private var engine = Engine.pi.rawValue
    @AppStorage("piProvider") private var provider = "openrouter"
    @AppStorage("settingsTab") private var tab = "building"
    @AppStorage("notify") private var notify = true
    @AppStorage("commandApproval") private var approval = CommandApproval.risky.rawValue
    private var approvalChoice: Binding<String> {   // a saved "auto" or "unusual" from before shows as Only when risky
        Binding(get: { CommandApproval(rawValue: approval)?.rawValue ?? CommandApproval.risky.rawValue }, set: { approval = $0 })
    }
    @AppStorage("askOutsideFolder") private var askOutsideFolder = true
    @AppStorage("shareAppLog") private var shareLog = true
    @AppStorage("shareAppPictures") private var sharePictures = true
    @State private var model = Builder.piModel
    @State private var revision = 0   // bumps after key changes so the view re-reads KeyStore
    @State private var notificationsDenied = false

    private var selectedEngine: Engine { Engine(rawValue: engine) ?? .pi }

    // Claude Code's and Codex's sign-ins, checked whenever the agent or where its tool was found changes. Kept
    // per engine, so a check or browser sign-in that finishes after the agent changed only updates its own.
    @State private var signIns: [Engine: Bool] = [:]
    @State private var signingIn: Engine?
    private var signedIn: Bool? { signIns[selectedEngine] }
    /// Changes when a copy of the tool arrives or is updated, as well as with the agent.
    private var signInCheck: String { _ = downloads.revision; return "\(engine) \(EngineInstall.path(for: selectedEngine) ?? "")" }

    /// What stands between the chosen agent and building, if anything.
    private enum Readiness { case ready, checking, downloading, signedOut, problem(String) }

    private var readiness: Readiness {
        _ = revision
        _ = downloads.revision
        guard selectedEngine != .pi else { return Builder.problem().map(Readiness.problem) ?? .ready }
        guard EngineInstall.path(for: selectedEngine) != nil else {
            return downloads.failure[selectedEngine].map(Readiness.problem) ?? .downloading
        }
        switch signedIn {
        case nil: return .checking
        case false?: return .signedOut
        case true?: return Builder.problem().map(Readiness.problem) ?? .ready
        }
    }

    /// Not Ready beside the menu when something's wrong (ready says nothing). Where Claude Code or Codex was
    /// found is in its help, for working out which copy runs when there are several.
    @ViewBuilder private var agentStatus: some View {
        Group {
            switch readiness {
            case .ready, .downloading: EmptyView()
            case .checking: ProgressView().controlSize(.small)
            default: NotReadyBadge()
            }
        }
        .help(EngineInstall.path(for: selectedEngine).map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "")
    }

    /// When the agent isn't ready: why, and the one thing that fixes it.
    @ViewBuilder private var agentFix: some View {
        switch readiness {
        case .downloading:
            LabeledContent("Downloading \(selectedEngine.title)…") {
                ProgressView(value: downloads.progress[selectedEngine] ?? 0).frame(width: 140)
            }
        case .problem(let problem) where selectedEngine != .pi && EngineInstall.path(for: selectedEngine) == nil:
            LabeledContent(problem) {
                Button("Try Again") { downloads.start(selectedEngine) }
            }
        case .signedOut:
            LabeledContent("Sign in to \(selectedEngine.title) to build with it.") {
                if signingIn == selectedEngine {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Finish in your browser…").foregroundStyle(.secondary)
                        Button("Cancel") { EngineSignIn.cancelSignIn(selectedEngine) }
                    }
                } else {
                    Button("Sign In…") { Task { await startSignIn() } }
                }
            }
        case .problem(let problem):
            Text(problem).foregroundStyle(.secondary).font(.callout)
        case .ready, .checking:
            EmptyView()
        }
    }

    private func checkSignIn() async {
        let engine = selectedEngine
        guard engine != .pi, EngineInstall.path(for: engine) != nil else { return }
        signIns[engine] = nil
        let signedIn = await EngineSignIn.isSignedIn(engine) ?? true   // can't tell: don't hold it up
        // The check's process outlives a cancelled task; a newer check of this engine has the say.
        guard !Task.isCancelled else { return }
        signIns[engine] = signedIn
    }

    private func startSignIn() async {
        let engine = selectedEngine
        signingIn = engine
        defer { if signingIn == engine { signingIn = nil } }
        _ = await EngineSignIn.signIn(engine)
        signIns[engine] = await EngineSignIn.isSignedIn(engine) ?? true
    }

    /// OpenRouter, once its key is added in Settings → AI Providers, or while it builds even if its key was removed.
    private var openRouterAdded: Bool {
        _ = revision
        return Provider.hasKey || (selectedEngine == .pi && provider != Builder.localProvider)
    }

    /// The provider menu's last item switches to the Providers tab instead of choosing a provider.
    private static let configure = Icons.configureProviders
    private var providerChoice: Binding<String> {
        Binding(get: { provider }, set: { if $0 == Self.configure { tab = "providers" } else { provider = $0 } })
    }

    /// One menu for what builds apps, as Settings → Apps lists what answers inside them: the models under
    /// what runs them (Claude Code, Codex, OpenRouter, Native Mac AI). OpenRouter's long list is the suggested
    /// models and the current one, with "Other model…" opening the search.
    private struct TextChoice: Identifiable { let id: String; let label: String }
    private struct TextGroup: Identifiable { let title: String; let items: [TextChoice]; var id: String { title } }

    @State private var otherModel = false   // "Other model…" chosen: the search list is shown

    private var textChoices: [TextGroup] {
        _ = revision
        var groups: [TextGroup] = []
        // The sign-ins, each model they offer. Always listed: choosing one downloads Lamp's copy when the Mac has none, and the
        // sign-in is asked for below the menu. The tool's own default stays on offer, so the account's choice
        // can be returned to.
        groups.append(TextGroup(title: Engine.claude.title, items: Builder.claudeModels.map { TextChoice(id: "claude:\($0.id)", label: $0.label) }))
        groups.append(TextGroup(title: Engine.codex.title, items: Builder.codexModels.map { TextChoice(id: "codex:\($0.id)", label: $0.label) }))
        if openRouterAdded {
            var items = Provider.models.map { TextChoice(id: "pi:openrouter:\($0.id)", label: $0.label) }
            let current = Builder.piModel(for: "openrouter")
            if !current.isEmpty, !Provider.models.contains(where: { $0.id == current }) {
                items.append(TextChoice(id: "pi:openrouter:\(current)", label: current))
            }
            items.append(TextChoice(id: "pi-other:openrouter", label: "Other model…"))
            groups.append(TextGroup(title: Provider.openRouter, items: items))
        }
        var onMac = local.installed.filter { !LocalModels.isDecisionModel($0.id) }
            .map { TextChoice(id: "pi:\(Builder.localProvider):\($0.id)", label: $0.name) }
        if onMac.isEmpty { onMac.append(TextChoice(id: "pi-other:\(Builder.localProvider)", label: "No models yet")) }
        groups.append(TextGroup(title: "Native Mac AI", items: onMac))
        return groups
    }

    private var textChoice: Binding<String> {
        Binding(get: {
            _ = revision
            switch selectedEngine {
            case .claude: return "claude:\(Builder.engineModel(.claude))"
            case .codex: return "codex:\(Builder.engineModel(.codex))"
            case .pi: return otherModel || model.isEmpty ? "pi-other:\(provider)" : "pi:\(provider):\(model)"
            }
        }, set: { choice in
            if choice == Self.configure { tab = "providers"; return }
            let parts = choice.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            switch parts[0] {
            case "claude", "codex":
                let which: Engine = parts[0] == "claude" ? .claude : .codex
                Builder.setEngineModel(parts.count > 1 ? parts[1] : "", for: which)
                engine = which.rawValue
                otherModel = false
                downloads.start(which)
            case "pi":
                // The model is saved under its provider before the provider changes, so the change reads it back.
                Builder.piProvider = parts[1]
                Builder.piModel = parts[2]
                provider = parts[1]
                model = parts[2]
                engine = Engine.pi.rawValue
                otherModel = false
            case "pi-other":
                provider = parts[1]
                engine = Engine.pi.rawValue
                otherModel = true
            default: break
            }
            revision += 1
        })
    }

    var body: some View {
        Form {
            Section("AI settings for Lamp") {
                LabeledContent("Text generation") {
                    HStack(spacing: 10) {
                        agentStatus
                        Picker("Text generation", selection: textChoice) {
                            ForEach(textChoices) { group in
                                Section(group.title) {
                                    ForEach(group.items, id: \.id) { Text($0.label).tag($0.id) }
                                }
                            }
                            Divider()
                            Text("Configure providers…").tag(Self.configure)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                agentFix
                if selectedEngine == .pi {
                    // Keys are managed in Providers; only ask here if the chosen provider has lost its key.
                    if provider != Builder.localProvider, !Provider.hasKey {
                        KeyRow(provider: Provider.openRouterProvider) { revision += 1; recheck() }
                    }
                    if otherModel { ModelPicker(provider: provider, model: $model, revision: revision) }
                }
                let _ = revision
                ImageModelRow(selection: Binding(get: { Icons.iconModel }, set: { Icons.iconModel = $0; revision += 1 }), forIcons: true)
                Picker("Ask before running commands", selection: approvalChoice) {
                    ForEach(CommandApproval.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if (CommandApproval(rawValue: approval) ?? .risky).isAutomatic && CommandApproval.claudeAutoUnavailable && selectedEngine == .claude {
                    Text("Claude's auto mode isn't available for your account, so Lamp asks before every command.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Permissions and Privacy") {
                SettingsCheckboxes {
                    Toggle("Ask before the agent opens files outside an app's folder", isOn: $askOutsideFolder)
                    Toggle("Show the agent what an app prints while it runs", isOn: $shareLog)
                    Toggle("Let the agent see the content of app windows", isOn: $sharePictures)
                    Toggle("Notify me when an app is ready or needs me", isOn: $notify)
                }
                if notify && notificationsDenied {
                    HStack {
                        Text("Notifications are turned off for Lamp in System Settings.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open System Settings") {
                            let id = Bundle.main.bundleIdentifier ?? ""
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!)
                        }
                        .controlSize(.small)
                    }
                }
            }
            // A phone in the list needs a team before an app can go on it, so the team is chosen here even
            // before there is an iPhone app.
            PhoneSigningSection(phoneApps: hasPhoneApps || store.devices.contains { $0.kind.isPhone })
            DevicesSection()
        }
        .settingsPane()
        .onChange(of: notify) { Notifier.shared.setBadge(store.unread.count) }
        .task { notificationsDenied = await Notifier.shared.isDenied() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { notificationsDenied = await Notifier.shared.isDenied() }
            revision += 1   // keys may have changed meanwhile
        }
        .onChange(of: engine) { recheck() }
        .onAppear { downloads.start(selectedEngine) }   // chosen before Lamp kept its own copy
        .task(id: signInCheck) { await checkSignIn() }
        .onChange(of: provider) { model = Builder.piModel; recheck() }
        .onChange(of: model) { Builder.piModel = model; recheck() }
        .onAppear { revision += 1 }   // keys may have changed in the Providers tab
    }

    private func recheck() { Task { await store.recheckSetup() } }

    /// Signing for a phone only matters to someone with an iPhone or iPad app.
    private var hasPhoneApps: Bool { store.everyApp.contains { $0.hasIOS } }
}

/// The AI, images and decisions that apps use while they run.
struct AppsSettings: View {
    @EnvironmentObject private var store: Store
    @AppStorage("appModel") private var appModel = AppAI.defaultRoute.id
    @ObservedObject private var local = LocalModels.shared
    @AppStorage("settingsTab") private var settingsTab = "building"
    @AppStorage("settingsSheet") private var settingsSheet = ""
    @AppStorage("imageModel") private var imageModel = Icons.artModels[0].id
    @AppStorage("decisionModel") private var decisionModel = AppAI.decisionModel.id
    @State private var revision = 0   // bumps after key changes so the view re-reads KeyStore

    var body: some View {
        Form {
            // Each menu lists only what can be used now, showing what apps actually get when the saved choice
            // can't be (its key was removed, say). With one thing it's named, not a menu; with nothing, Not
            // Ready stands in its place.
            Section("Models used in apps") {
                let _ = revision   // re-read KeyStore after keys change
                let textGroups = AppAI.textRouteGroups(including: nil)
                if textGroups.isEmpty {
                    NotReadyRow(title: "Text generation")
                    CapabilityNote(capability: .text)
                } else if textGroups.count == 1, let only = textGroups[0].routes.first, textGroups[0].routes.count == 1 {
                    LabeledContent("Text generation", value: only.label)
                } else {
                    Picker("Text generation", selection: Binding(get: { AppAI.route(for: appModel).id }, set: { appModel = $0 })) {
                        ForEach(textGroups, id: \.title) { group in
                            Section(group.title) { ForEach(group.routes) { Text($0.name).tag($0.id) } }
                        }
                    }
                }

                ImageModelRow(selection: $imageModel)

                let decisions = decisionChoices
                if decisions.isEmpty {
                    NotReadyRow(title: "Decision model")
                    CapabilityNote(capability: .decisions)
                } else if decisions.count == 1 {
                    // decisionRoute falls back to the one that can answer, so naming it is naming what's used.
                    LabeledContent("Decision model", value: decisions[0].label)
                } else {
                    // What AppAI.decide actually uses, which is the saved choice only when that can answer.
                    Picker("Decision model", selection: Binding(get: {
                        _ = decisionModel
                        return AppAI.decisionRoute(for: nil)?.id ?? decisions[0].id
                    }, set: { decisionModel = $0 })) {
                        ForEach(decisions, id: \.id) { Text($0.label).tag($0.id) }
                    }
                }
            }
            // Only for someone with an iPhone or iPad app: nothing else goes on a phone.
            if store.everyApp.contains(where: { $0.hasIOS }) { PhoneAwaySection(revision: revision) }
            ComputerUseSettings()
        }
        .settingsPane()
        .onAppear { revision += 1 }   // keys may have changed in the Providers tab
    }

    /// The decision models that can answer now: those with their key, the one on this Mac once it's
    /// downloaded, and the text model when something answers apps.
    private var decisionChoices: [(id: String, label: String, provider: String, model: String)] {
        _ = revision
        _ = local.installed
        return AppAI.decisionModels.filter { AppAI.canDecide(with: $0) }
    }
}

/// The Apple team Lamp signs for, in Building: an iPhone or iPad app's phone builds and the Mac half of an app
/// for both, and a Mac app, which macOS then lets offer its actions to Siri, Shortcuts and Spotlight. Where an
/// app opens (a simulator or a phone) is chosen per app under Try On. Shown with an iPhone or iPad app, which
/// needs a team, or when this Mac has a team's certificate to sign a Mac app with; a Mac app can do without
/// one, so only then is None a choice and nothing is chosen for the person.
struct PhoneSigningSection: View {
    let phoneApps: Bool
    @AppStorage("appleTeam") private var team = ""
    @State private var teams: [(id: String, name: String)] = []
    /// Free accounts' teams, named as Xcode names them: two teams of one person otherwise read the same.
    @State private var free: Set<String> = []
    @State private var teamless = 0

    var body: some View {
        Group {
            if phoneApps || !teams.isEmpty {
                Section("Signing") {
                    if teams.isEmpty {
                        TextField("Apple Team ID", text: $team, prompt: Text("Ten letters and digits, from Xcode → Settings → Accounts"))
                    } else {
                        Picker("Apple Team", selection: $team) {
                            if !phoneApps { Text("None").tag("") }
                            // Xcode may already name a free team "… (Personal Team)": said once.
                            ForEach(teams, id: \.id) { team in
                                let mark = free.contains(team.id) && !team.name.localizedCaseInsensitiveContains("Personal Team") ? "Personal Team, " : ""
                                Text("\(team.name) (\(mark)\(team.id))").tag(team.id)
                            }
                            if !team.isEmpty, !teams.contains(where: { $0.id == team }) { Text(team).tag(team) }
                        }
                    }
                    if phoneApps, teamless > 0 {
                        Text("An Apple Account in Xcode has no team yet. In Xcode → Settings → Apple Accounts, choose its team, click Manage Certificates, then + and Apple Development.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: phoneApps) {
            teams = await Devices.knownTeams()
            free = PhoneTools.xcodeFreeTeams()
            teamless = PhoneTools.xcodeAccountsWithoutTeams()
            guard phoneApps else { return }
            // The account signed in to Xcode is the one that can sign, so its team is the first choice
            // whenever the stored one isn't among Xcode's.
            let signedIn = Devices.xcodeTeams()
            if let first = signedIn.first, !signedIn.contains(where: { $0.id == team }) { team = first.id }
            else if team.isEmpty, let first = teams.first { team = first.id }
        }
    }
}

/// Every device Lamp knows about, in Building: this Mac, and the iPhones, iPads and Apple Watches it can see,
/// each by its exact model and software, with where its setup stands and the one thing that takes it further.
/// Nothing is set up in advance: a device is set up when the person asks, here or when a wish needs it. Where
/// an app opens is chosen per app under Try On, which lists the same phones.
struct DevicesSection: View {
    @EnvironmentObject private var store: Store
    @AppStorage("appleTeam") private var team = ""
    @AppStorage(PhoneRenewals.staysOpenKey) private var keepOpening = false
    @State private var adding = false
    @State private var forgetting: Device?
    @State private var showingEverything = false

    var body: some View {
        let list = HomeNetwork.List(devices: [store.thisMac].compactMap { $0 } + store.devices, hosts: store.hosts)
        Section("Your Devices") {
            // What Lamp makes apps for or controls, then what it could learn, then the rest of the network, folded.
            ForEach(list.works + list.couldLearn) { device in
                row(device, controls: list.controls[device.id])
            }
            if !list.others.isEmpty || list.unnamed > 0 {
                DisclosureGroup(isExpanded: $showingEverything) {
                    ForEach(list.others) { host in hostRow(host) }
                    if list.unnamed > 0 {
                        Text(list.unnamed == 1 ? "1 more with a private address, most likely a phone, tablet or computer"
                             : "\(list.unnamed) more with private addresses, most likely phones, tablets and computers")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Everything Else on Your Network (\(list.others.count + list.unnamed))")
                }
            }
            if store.localNetworkRefused, !store.lookingForDevices { LocalNetworkRefused() }
            HStack {
                if store.lookingForDevices { LookingForDevices() }
                Spacer()
                Button("Add a New Device…") { adding = true }.controlSize(.small)
            }
            // Shown once an app is on a phone, which is when it does something, and while it's on, so it can always be
            // turned off: Lamp keeps opening at login until it is.
            if keepOpening || PhoneRenewals.anyOnPhones(store.projects) {
                SettingsCheckboxes {
                    Toggle("Keep apps on your phones opening", isOn: Binding(get: { keepOpening }, set: { store.keepPhoneAppsOpening($0) }))
                        .checkboxNote("Lamp opens when you log in and keeps running with its window closed, to put them back before Apple stops them opening.")
                }
            }
        }
        .onAppear { store.refreshDevices(everything: true) }
        .sheet(isPresented: $adding) { AddDeviceSheet() }
        .confirmationDialog(forgetting.map { "Forget \($0.name)?" } ?? "", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
            Button("Forget", role: .destructive) { if let device = forgetting { forget(device) } }
        } message: {
            Text("Lamp forgets how to reach it and what you typed for it. To use it again, set it up from the start.")
        }
    }

    /// A device Lamp set up itself, on the network: the ones Reconnect and Forget are for. A phone's pairing is the
    /// Mac's, and an Android device's is the device's own.
    private func keptByLamp(_ device: Device) -> Bool {
        device.kind.isTV ? TVs.kept().contains { $0.id == device.id } : device.kind == .other && Integrations.kept(device.id) != nil
    }

    /// Reconnect: a TV's setup window, checked again from where it stands; another device's setup from the start, its
    /// certificate let go, so a reset device or one whose developer mode was turned on again is trusted afresh.
    private func reconnect(_ device: Device) {
        if device.kind.isTV {
            TVs.reconnect(device.id)
            store.refreshDevices()
            TVSetup.shared.show(device.udid)
        } else {
            DeviceSetupModel.for(device).reconnect()
            DeviceSetupWindow.show(device)
        }
    }

    private func forget(_ device: Device) {
        if device.kind.isTV {
            TVs.forget(device.id)
        } else {
            DeviceSetupModel.discard(device.id)
            Integrations.forget(device.id)
        }
        forgetting = nil
        store.refreshDevices()
    }

    /// A host nothing of Lamp's works with: what it is, and the names it goes by on the network, on this Mac only.
    private func hostRow(_ host: NetworkHost) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: host.isGateway ? "wifi.router" : "network").foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(HomeNetwork.label(host))
                Text((host.names.prefix(2) + [host.address]).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .help(HomeNetwork.facts(host))
    }

    private func row(_ device: Device, controls: String? = nil) -> some View {
        let setup = device.setup(team: team)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: device.kind.symbol).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                Text(device.line).font(.caption).foregroundStyle(.secondary)
                let stopped = store.projects.filter { PhoneRenewals.stoppedOpening($0, on: device.udid) }.map(\.name)
                if !stopped.isEmpty {
                    Label("\(TeamLimits.list(stopped)) stopped opening. Open \(stopped.count == 1 ? "it" : "each") and press Play.", systemImage: "exclamationmark.circle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            switch setup {
            case _ where controls != nil:
                Text("Apps can control it").foregroundStyle(.secondary).help(controls ?? "")
            case _ where device.isAway:
                Text(device.status).foregroundStyle(.secondary)
                    .help("Lamp didn't find it on this network just now. It may be off, or somewhere else.")
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
            case .needs(let step) where device.kind == .other && device.integration == nil:
                // Found on the network, with nothing yet that knows it: not a problem, an offer.
                Text(step).foregroundStyle(.secondary)
                DeviceNextStep(device: device)
            case .needs(let step):
                Label(step, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange).labelStyle(.titleAndIcon)
                DeviceNextStep(device: device)
            case .talkOnly:
                Text(setup.words).foregroundStyle(.secondary)
            }
            if keptByLamp(device) {
                Menu {
                    Button("Reconnect…") { reconnect(device) }
                    Button("Forget \(device.name)…") { forgetting = device }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Reconnect or forget \(device.name)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// macOS refused the last look on the network, said where a look was asked for, with the way to allow Lamp there.
/// System Settings opens on Privacy & Security, not on Local Network itself (it has no link to that page), so the
/// line says where to go from there.
struct LocalNetworkRefused: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Lamp can't look on your local network.", systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
                Button("Allow…") { NSWorkspace.shared.open(Store.localNetworkSettings) }.controlSize(.small)
            }
            Text("In Privacy & Security, choose Local Network and turn on Lamp.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A look for devices going on, said where it was asked for.
struct LookingForDevices: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Looking for devices…").foregroundStyle(.secondary)
        }
    }
}

/// Where a new device starts, from Your Devices: each kind Lamp can set up, the way it's reached, and what's on the
/// network now that isn't set up yet. Each kind's setup has a window of its own, checked and taken further there,
/// so choosing one closes this. The network is looked at again as this opens and when asked.
struct AddDeviceSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    /// Found on the network and not set up: the TVs and the devices an integration finds or nothing knows yet. Phones
    /// and tablets have their own rows above, whose setup windows take each one further, so a wireless one isn't here.
    private var waiting: [Device] {
        let controlled = HomeNetwork.List(devices: store.devices, hosts: store.hosts).controls
        return store.devices.filter { ($0.kind.isTV || $0.kind == .other) && $0.reach == .network && $0.setup() != .ready && controlled[$0.id] == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a New Device").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                kind("iPhone or iPad", symbol: "iphone", how: "Plug it into this Mac and unlock it.") {
                    PhoneSetup.shared.show()
                }
                kind("Android phone or tablet", symbol: "smartphone", how: "Plug it into this Mac.") {
                    AndroidSetup.shared.show()
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "tv").foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TV or other device")
                        Text("Turn it on, on this Mac's network.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(waiting) { device in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: device.kind.symbol).foregroundStyle(.secondary).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                Text(device.line).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            DeviceNextStep(device: device, then: { dismiss() })
                        }
                    }
                    HStack {
                        if store.lookingForDevices {
                            LookingForDevices()
                        } else if store.localNetworkRefused {
                            LocalNetworkRefused()
                        } else {
                            Text(waiting.isEmpty ? "Nothing new found." : "").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Look Again") { store.refreshDevices(everything: true) }.controlSize(.small).disabled(store.lookingForDevices)
                    }
                }
                .padding(.leading, 30)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { store.refreshDevices(everything: true) }
    }

    private func kind(_ name: String, symbol: String, how: String, setUp: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(how).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Set Up…") { dismiss(); setUp() }.controlSize(.small)
        }
    }
}

/// The one button that takes a device to its next step, where Lamp can do it from here; `then` runs once a window
/// for it has been asked for.
struct DeviceNextStep: View {
    @EnvironmentObject private var store: Store
    let device: Device
    var then: () -> Void = {}

    var body: some View { next(for: device) }

    @ViewBuilder private func next(for device: Device) -> some View {
        if device.kind.isPhone, !device.paired {
            Button(store.pairing.contains(device.udid) ? "Pairing…" : "Pair…") { store.pairDevice(device, for: nil) }
                .controlSize(.small).disabled(store.pairing.contains(device.udid))
        } else if device.kind.isPhone, !device.developerMode {
            Button("How…") { then(); PhoneSetup.shared.show(family: device.family ?? .iphone, phone: device.udid) }.controlSize(.small)
        } else if device.kind.isTV {
            Button("Set Up…") { then(); TVSetup.shared.show(device.udid) }.controlSize(.small)
        } else if device.kind == .other {
            // One Lamp has an integration for is set up in the window drawn from it; one it doesn't know yet starts
            // the work of writing its integration, in a wish of its own.
            Button("Set Up…") {
                then()
                if device.integration != nil { DeviceSetupWindow.show(device) } else { store.setUpDevice(device) }
            }
            .controlSize(.small)
        }
    }
}

/// What an app on the person's own phone uses when it can't reach this Mac, in Apps. Then it can only reach
/// OpenRouter, so these are OpenRouter's models, and that's the one thing a phone needs a key for.
struct PhoneAwaySection: View {
    @AppStorage("awayModel") private var awayModel = ""
    @AppStorage("awayImageModel") private var awayImageModel = ""
    @AppStorage("awayDecisionModel") private var awayDecisionModel = ""
    let revision: Int

    var body: some View {
        Section("On a phone away from this Mac") {
            let _ = revision   // re-read KeyStore after keys change
            if Provider.hasKey {
                Picker("Text generation", selection: Binding(get: { AppAI.awayModel.id }, set: { awayModel = $0 })) {
                    ForEach(AppAI.anthropicModels, id: \.id) { Text($0.label).tag($0.id) }
                }
                Picker("Image model", selection: Binding(get: { AppAI.awayImageModel }, set: { awayImageModel = $0 })) {
                    ForEach(Icons.artModels, id: \.id) { Text($0.label).tag($0.id) }
                }
                // Only what a phone can carry the key for; a choice whose key is gone shows the text
                // route that stands in for it, as Store.keysForPhone does.
                let awayDecisions = AppAI.awayDecisionModels.filter { $0.provider == "text" || $0.provider == "openrouter" || KeyStore.key(for: $0.provider) != nil }
                Picker("Decision model", selection: Binding(get: {
                    _ = awayDecisionModel
                    let chosen = AppAI.awayDecisionModel.id
                    return awayDecisions.contains { $0.id == chosen } ? chosen : awayDecisions.first { $0.provider == "text" }!.id
                }, set: { awayDecisionModel = $0 })) {
                    ForEach(awayDecisions, id: \.id) { Text($0.label).tag($0.id) }
                }
            } else {
                NotReadyRow(title: "Text generation")
                CapabilityNote(capability: .text, context: .phoneAway)
            }
        }
    }
}

/// Turns apps' use of the other apps on the Mac (LampComputer) on or off. Turning it on installs CuaDriver if
/// needed and asks for its permissions; turning it off stops apps using it (CuaDriver stays installed).
struct ComputerUseSettings: View {
    @AppStorage("computerUse") private var enabled = false
    @AppStorage("codexComputerUseOff") private var codexOff = false
    @State private var status: ComputerUse.Status?
    @State private var working: String?
    @State private var problem: String?

    var body: some View {
        Section("Permissions and Privacy") {
            // The choice of what does the clicking is a part of the first checkbox, so it's indented under it.
            SettingsCheckboxes {
                Toggle("Let apps use your other apps", isOn: Binding(get: { enabled }, set: { on in
                    if on { Task { await turnOn() } } else { enabled = false; problem = nil }
                }))
                .disabled(working != nil)
                .checkboxNote("Lets your apps read and use your other apps, such as Slack, Mail, or Gmail and LinkedIn in your browser, with the accounts you're already signed in to. Apps ask before every click or keystroke."
                              + (CodexComputerUse.server == nil ? " Turning it on adds CuaDriver (from Cua, open source) to Applications, and macOS asks you to allow it Accessibility and Screen Recording." : ""))
                if enabled, CodexComputerUse.server != nil {
                    // The ChatGPT app's Computer Use is on this Mac: it does the looking and clicking, unless the
                    // person would rather keep CuaDriver. A part of the first, so shown only while it's on.
                    Toggle("Use the ChatGPT app's Computer Use", isOn: Binding(get: { !codexOff }, set: { useCodex in
                        codexOff = !useCodex
                        // Back to CuaDriver while the feature is on: it has to be installed and allowed, like a first turn-on.
                        Task { if enabled, !useCodex { await turnOn() } else { status = await ComputerUse.status() } }
                    }))
                    .disabled(working != nil)
                    .checkboxNote(codexOff
                                  ? "CuaDriver (from Cua, open source) does the looking and clicking instead: macOS asks you to allow it Accessibility and Screen Recording."
                                  : "It does the looking and clicking in the background, with the permissions you gave it there. Turn it off to use CuaDriver instead.")
                    .underCheckbox()
                }
            }
            if let working {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(working).foregroundStyle(.secondary) }
                    .font(.callout)
            } else if enabled, status == .needsPermission {
                LabeledContent("CuaDriver needs permission") {
                    Button("Allow Access…") { Task { await allow() } }
                }
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { status = await ComputerUse.status() }
    }

    private func turnOn() async {
        problem = nil
        if CodexComputerUse.isAvailable {   // nothing to install: the ChatGPT app's helper has the permissions
            status = .ready
            enabled = true
            return
        }
        do {
            try await ComputerUse.install { working = $0 }
            status = await ComputerUse.status()
            if status != .ready { await allow() }
            enabled = status == .ready
        } catch {
            problem = error.localizedDescription
        }
        working = nil
    }

    private func allow() async {
        working = "Waiting for you to allow access in System Settings…"
        await ComputerUse.requestPermissions()
        status = await ComputerUse.status()
        working = nil
        if status == .ready {
            enabled = true
        } else {
            problem = "CuaDriver doesn't have both permissions yet. Allow Accessibility and Screen Recording for CuaDriver in System Settings → Privacy & Security, then try again."
        }
    }
}

/// Claude, ChatGPT, OpenRouter and Native Mac AI in one list, each with its state. Double-click one to see its
/// models, sign in, or change its key.
struct ProvidersSettings: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var local = LocalModels.shared
    @AppStorage("settingsSheet") private var pendingSheet = ""   // set by the setup screen
    @State private var selection: String?
    @State private var showing: ProviderDetail?
    @State private var removing: PiProvider?
    @State private var revision = 0   // bumps after key changes so the view re-reads KeyStore
    @State private var signedIn: [Engine: Bool?] = [:]
    @ObservedObject private var downloads = EngineDownloads.shared

    /// Every provider, in the welcome's order: the sign-ins (downloaded or not, since this is where Building's
    /// Configure providers… leads), the key, then the models on this Mac.
    private var providers: [String] {
        [Engine.claude, .codex].map { "engine:\($0.rawValue)" } + Provider.keyProviders.map(\.id) + [Builder.localProvider]
    }

    /// One row: logo, name and state. What each is used for is chosen, and shown, in Building and Apps.
    private func row(_ id: String) -> some View {
        HStack(spacing: 10) {
            ProviderLogo(id: id, size: 24)
            Text(ProviderDetail.name(id))
            Spacer()
            Text(detail(id)).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .tag(id)
    }

    private func list(_ rows: [String]) -> some View {
        List(rows, id: \.self, selection: $selection) { id in row(id) }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first {
                    if id.hasPrefix("engine:") {
                        Button("Sign In…") { showing = ProviderDetail(id) }
                    } else {
                        Button(Provider.keyProvider(id) == nil ? "Show Models…" : "Edit…") { showing = ProviderDetail(id) }
                    }
                    if let provider = Provider.keyProvider(id), KeyStore.key(for: id) != nil {
                        Button("Remove Key…", role: .destructive) { removing = provider }
                    }
                }
            } primaryAction: { ids in
                showing = ids.first.map(ProviderDetail.init)
            }
            .onDeleteCommand { removing = selection.flatMap(Provider.keyProvider).flatMap { KeyStore.key(for: $0.id) == nil ? nil : $0 } }
            .scrollDisabled(true)
            .frame(height: CGFloat(max(rows.count, 1)) * 40)
    }

    var body: some View {
        Form {
            Section {
                list(providers)
            }
        }
        .settingsPane()
        .sheet(item: $showing) { detail in
            switch detail {
            case .key(let provider): ProviderSheet(provider: provider) { changed() }
            case .local: LocalAISheet()
            case .engine(let engine): EngineSheet(engine: engine, signedIn: signedIn[engine] ?? nil) { refreshSignIns() }
            }
        }
        .confirmationDialog("Remove \(removing?.name ?? "provider")?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let removing { KeyStore.setKey(nil, for: removing.id) }
                selection = nil
                changed()
            }
        } message: {
            Text("Lamp forgets its API key. Apps and builds that use it stop working until you add it again.")
        }
        .onAppear { openPending(); refreshSignIns(); KeyStore.preload() }   // a key declined at launch is asked for again
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSignIns()
        }
        .onChange(of: downloads.revision) { refreshSignIns() }
        .onReceive(NotificationCenter.default.publisher(for: KeyStore.changed)) { _ in revision += 1 }
        .onChange(of: pendingSheet) { openPending() }
        .task { local.refresh() }
    }

    private func refreshSignIns() {
        Task {
            for engine in [Engine.claude, .codex] where EngineInstall.path(for: engine) != nil {
                signedIn[engine] = await EngineSignIn.isSignedIn(engine)
            }
        }
    }

    private func detail(_ id: String) -> String {
        if id.hasPrefix("engine:"), let engine = Engine(rawValue: String(id.dropFirst(7))) {
            _ = revision
            if downloads.isDownloading(engine) { return "Downloading…" }
            guard EngineInstall.path(for: engine) != nil else { return "Not signed in" }
            switch signedIn[engine] {
            case .some(.some(true)): return "Signed in"
            case .some(.some(false)): return "Not signed in"
            default: return "Checking…"
            }
        }
        if id == Builder.localProvider {
            guard !local.installed.isEmpty else { return "No models yet" }
            let bytes = local.installed.reduce(Int64(0)) { $0 + $1.bytes }
            return "\(Self.models(local.installed.count)) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        }
        _ = revision
        guard KeyStore.key(for: id) != nil else { return "Not added" }
        return KeyStore.usesKeychain ? "Key in Keychain" : "Key saved"
    }

    private static func models(_ count: Int) -> String { count == 1 ? "1 model" : "\(count) models" }

    private func openPending() {
        guard !pendingSheet.isEmpty else { return }
        showing = ProviderDetail(pendingSheet)
        pendingSheet = ""
    }

    private func changed() {
        revision += 1
        Task { await store.recheckSetup() }
    }
}

/// What double-clicking a provider opens.
private enum ProviderDetail: Identifiable {
    case key(PiProvider)
    case local
    case engine(Engine)

    init(_ id: String) {
        if id.hasPrefix("engine:"), let engine = Engine(rawValue: String(id.dropFirst(7))) { self = .engine(engine) }
        else if let provider = Provider.keyProvider(id) { self = .key(provider) }
        else { self = .local }
    }

    var id: String {
        switch self {
        case .key(let provider): provider.id
        case .local: Builder.localProvider
        case .engine(let engine): "engine:\(engine.rawValue)"
        }
    }

    static func name(_ id: String) -> String {
        if id == Builder.localProvider { return "Native Mac AI" }
        if id.hasPrefix("engine:"), let engine = Engine(rawValue: String(id.dropFirst(7))) { return engine.title }
        return Provider.keyProvider(id)?.name ?? id
    }
}

/// Claude Code or Codex: signed in or not, and the way to sign in. Signing in first downloads Lamp's own
/// copy when there isn't one yet. What they do for Lamp is on the row.
private struct EngineSheet: View {
    let engine: Engine
    let signedIn: Bool?
    let changed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloads = EngineDownloads.shared
    @State private var working = false

    private var detail: String {
        if let failure = downloads.failure[engine], EngineInstall.path(for: engine) == nil { return failure }
        if downloads.isDownloading(engine) { return "Downloading \(engine.title)…" }
        if EngineInstall.path(for: engine) == nil { return "Not signed in yet." }
        switch signedIn {
        case true?: return "Signed in. Builds apps and answers inside them with your \(engine == .claude ? "Claude" : "ChatGPT") subscription."
        case false?: return "Not signed in yet."
        case nil: return "Checking the sign-in…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProviderHeader(id: "engine:\(engine.rawValue)", detail: detail)
            if downloads.isDownloading(engine) {
                ProgressView(value: downloads.progress[engine] ?? 0)
            }
            if Store.shared.everyApp.contains(where: { $0.hasIOS }) {   // said only to someone it concerns
                Text("The sign-in stays on this Mac: iOS apps can use it only on the same Wi‑Fi network as it. Away from it they need an OpenRouter key.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if working {
                    Button("Cancel Sign-In") { EngineSignIn.cancelSignIn(engine) }
                } else {
                    Button("Sign In…") {
                        working = true
                        Task { _ = await EngineSignIn.signIn(engine); working = false; changed() }
                    }
                    .keyboardShortcut(.defaultAction).disabled(signedIn == true)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Header shared by the provider sheets: logo, name and one line about it.
private struct ProviderHeader: View {
    let id: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            ProviderLogo(id: id, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(ProviderDetail.name(id)).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Add, replace or remove one provider's API key.
private struct ProviderSheet: View {
    let provider: PiProvider
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @StateObject private var check = KeyCheck()
    private let hasKey: Bool

    init(provider: PiProvider, onChange: @escaping () -> Void) {
        self.provider = provider
        self.onChange = onChange
        hasKey = KeyStore.key(for: provider.id) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProviderLogo(id: provider.id, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name).font(.headline)
                    Text(hasKey ? (KeyStore.usesKeychain ? "Key saved in Keychain" : "Key saved") : "Not added yet")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Form {
                SecureField(hasKey ? "New key" : "API key", text: $key, prompt: Text("Paste key"))
                    .onSubmit(save)
                    .onChange(of: key) { check.edited() }
                Link("Get a key from \(provider.name)", destination: URL(string: provider.keyURL)!)
                    .font(.callout)
            }
            if let problem = check.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if hasKey {
                    Button("Remove Key", role: .destructive) {
                        KeyStore.setKey(nil, for: provider.id)
                        onChange()
                        dismiss()
                    }
                    .disabled(check.checking)
                }
                Spacer()
                if check.checking { ProgressView().controlSize(.small) }
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(check.canSaveUnchecked ? "Save Anyway" : hasKey ? "Save" : "Add", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmed.isEmpty || check.checking)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onDisappear { check.cancel() }   // closed while OpenRouter was being asked: nothing is saved
    }

    private func save() {
        check.save(key, for: provider) {
            onChange()
            dismiss()
        }
    }
}

/// Saves a key typed into Settings, asking OpenRouter about its own first, as the key card in the chat does:
/// a key it refuses isn't saved, so a slip shows up here and not later as a build or a picture that fails.
///
/// Settings is also where a key is put in ahead of time, perhaps with no connection, so when OpenRouter
/// can't be asked the key isn't turned away: the person is told, and saving again keeps it unchecked.
@MainActor
final class KeyCheck: ObservableObject {
    @Published private(set) var checking = false
    @Published private(set) var problem: String?
    /// The key OpenRouter couldn't be asked about; saving it again goes ahead without asking.
    @Published private var unchecked: String?
    private var task: Task<Void, Never>?

    var canSaveUnchecked: Bool { unchecked != nil }

    /// The field changed: what was said about the old text no longer holds.
    func edited() {
        cancel()
        problem = nil
        unchecked = nil
    }

    func cancel() {
        task?.cancel()
        task = nil
        checking = false
    }

    /// `strict`, where the person can wait for OpenRouter's answer (the chat's setup card): a key it couldn't
    /// be asked about isn't saved, and there's no saving it anyway.
    func save(_ typed: String, for provider: PiProvider, strict: Bool = false, saved: @escaping () -> Void) {
        let key = typed.trimmed
        guard !key.isEmpty, !checking else { return }
        guard provider.id == "openrouter", key != unchecked || strict else {
            KeyStore.setKey(key, for: provider.id)
            edited()
            return saved()
        }
        checking = true
        problem = nil
        task = Task {
            let verdict = await SetupView.openRouterVerdict(key)
            guard !Task.isCancelled else { return }
            checking = false
            switch verdict {
            case .accepted:
                KeyStore.setKey(key, for: provider.id)
                saved()
            case .refused(let why):
                problem = why
            case .unchecked(let why) where strict:
                problem = why
            case .unchecked(let why):
                problem = why + " You can save the key without checking it."
                unchecked = key
            }
        }
    }
}

/// A provider's logo on a white rounded tile, like an app icon. Falls back to its initial.
struct ProviderLogo: View {
    let id: String
    let size: CGFloat

    private static var cache: [String: NSImage] = [:]
    /// Logos that are already a full icon, drawn edge to edge instead of on a tile.
    private static let fullBleed: Set<String> = []

    private var image: NSImage? {
        if let cached = Self.cache[id] { return cached }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("ProviderLogos/\(id).png"),
              let image = NSImage(contentsOf: url) else { return nil }
        Self.cache[id] = image
        return image
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            shape.fill(.white)
            if id == "lamp" {
                ChatLook.LampFlame().fill(.black).padding(size * 0.2)
            } else if id == Builder.localProvider {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: size * 0.5)).foregroundStyle(.black.opacity(0.75))
            } else if id.hasPrefix("engine:") {
                Image(systemName: id == "engine:claude" ? "asterisk" : "terminal")
                    .font(.system(size: size * 0.5)).foregroundStyle(.black.opacity(0.75))
            } else if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .padding(Self.fullBleed.contains(id) ? 0 : size * 0.18)
            } else {
                Text(ProviderDetail.name(id).prefix(1))
                    .font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.black.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
    }
}

/// API key for one provider: shows "saved" with a Remove button, or a field to add one.
struct KeyRow: View {
    let provider: PiProvider
    var label: String?
    var onChange: () -> Void
    @State private var key = ""
    @State private var saved = false
    @StateObject private var check = KeyCheck()

    var body: some View {
        Group {
            if saved {
                LabeledContent(label ?? "\(provider.name) key") {
                    HStack {
                        Text(KeyStore.usesKeychain ? "Saved in Keychain" : "Saved").foregroundStyle(.secondary)
                        Button("Remove", role: .destructive) {
                            KeyStore.setKey(nil, for: provider.id)
                            saved = false
                            onChange()
                        }
                    }
                }
            } else {
                LabeledContent(label ?? "\(provider.name) key") {
                    HStack {
                        SecureField("", text: $key, prompt: Text("Paste key"))
                            .onSubmit(save)
                            .onChange(of: key) { check.edited() }
                        if check.checking {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(check.canSaveUnchecked ? "Save Anyway" : "Save", action: save).disabled(key.trimmed.isEmpty)
                        }
                        Link("Get one", destination: URL(string: provider.keyURL)!)
                    }
                }
                if let problem = check.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { saved = KeyStore.key(for: provider.id) != nil }
        .onChange(of: provider) { saved = KeyStore.key(for: provider.id) != nil; key = "" }
        .onDisappear { check.cancel() }
    }

    private func save() {
        check.save(key, for: provider) {
            key = ""
            saved = true
            onChange()
        }
    }
}

/// Searchable model list for a provider (OpenRouter's, from pi's catalog, or the models on this Mac).
struct ModelPicker: View {
    let provider: String
    @Binding var model: String
    let revision: Int
    @ObservedObject private var local = LocalModels.shared
    @State private var models: [String] = []
    @State private var search = ""
    @State private var loading = false

    private var filtered: [String] {
        let query = search.trimmed.lowercased()
        return query.isEmpty ? models : models.filter { $0.lowercased().contains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Model") {
                Text(model.isEmpty ? "None chosen" : model).foregroundStyle(model.isEmpty ? .orange : .primary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if provider == Builder.localProvider && local.installed.isEmpty {
                Text("No models downloaded yet. Double-click Native Mac AI in AI Providers to get one.").font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("Search models", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if filtered.isEmpty && !search.trimmed.isEmpty { model = search.trimmed } }
                List(filtered, id: \.self, selection: Binding(get: { model }, set: { if let value = $0 { model = value } })) {
                    Text($0).tag($0)
                }
                .frame(height: 150)
                .overlay {
                    if loading { ProgressView().controlSize(.small) }
                    else if filtered.isEmpty {
                        Text(search.isEmpty ? "No models found" : "Press Return to use “\(search.trimmed)”")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: "\(provider)-\(revision)-\(local.installed.count)") { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        switch provider {
        case Builder.localProvider: models = local.installed.filter { !LocalModels.isDecisionModel($0.id) }.map(\.id)
        default: models = await Agent.listModels()
        }
        if provider == "openrouter" {   // suggested models first
            let suggested = Provider.models.map(\.id)
            models = suggested + models.filter { !suggested.contains($0) }
        }
        if model.isEmpty, let first = models.first { model = first }
    }
}

/// Native Mac AI: models on this Mac (shared with Local and the Hugging Face cache), plus downloads.
private struct LocalAISheet: View {
    @EnvironmentObject private var store: Store
    @AppStorage("decisionModel") private var decisionModel = AppAI.decisionModel.id
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var local = LocalModels.shared
    @ObservedObject private var images = ImageModels.shared
    @ObservedObject private var tools = PythonTools.shared
    @State private var repo = ""
    @State private var custom: [LocalModelSpec] = []
    @State private var adding = false
    @State private var addError: String?

    private var downloadable: [LocalModelSpec] {
        (LocalModels.catalog + LocalModels.decisionCatalog + custom).filter { !local.isInstalled($0) }
    }

    /// Tall enough for a good look at the list, short enough to leave the screen around it.
    private var listHeight: CGFloat {
        min(560, ((NSScreen.main?.visibleFrame.height ?? 800) - 320).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProviderHeader(id: Builder.localProvider,
                           detail: "Private and offline. Slower and less capable than the best cloud models, especially for whole apps.")
                .padding(20)
            Divider()
            Form {
                Section {
                    if local.installed.isEmpty {
                        Text("No models yet. Download one below.").foregroundStyle(.secondary)
                    }
                    ForEach(local.installed) { installedRow($0) }
                } header: { Text("On this Mac") } footer: {
                    Text("Shared with Local and other tools through the Hugging Face cache.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    ForEach(downloadable) { downloadRow($0) }
                    HStack {
                        TextField("owner/Model-GGUF or a Hugging Face link", text: $repo)
                        Button("Add") { add() }.disabled(repo.trimmed.isEmpty || adding)
                    }
                    if adding { ProgressView().controlSize(.small) }
                    if let addError { Text(addError).font(.caption).foregroundStyle(.red) }
                } header: { Text("Download") } footer: {
                    Text("This Mac has \(LocalModels.ramGB) GB of memory. Any model repo in GGUF form works: Lamp picks the version that fits a Mac best, with image support when the model has it.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    if !ImageModels.hasMflux {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("mflux").font(.headline)
                                Text("Runs picture models. A one-time install of about 1.3 GB.")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let error = tools.errors[.mflux] { Text(error).font(.caption).foregroundStyle(.red) }
                            }
                            Spacer()
                            if tools.installing.contains(.mflux) { ProgressView().controlSize(.small) }
                            else { Button("Install") { Task { await tools.install(.mflux) } } }
                        }
                    }
                    ForEach(ImageModels.catalog) { imageRow($0) }
                } header: { Text("Pictures") } footer: {
                    Text(ImageModels.ready
                         ? "Apps' pictures and icon artwork are made here with \(images.chosen?.name ?? "the chosen model") when there's no OpenRouter key. About 10–30 seconds a picture."
                         : "Pictures made on this Mac, free and private, when there's no OpenRouter key. Slower than the cloud models, and they can't edit existing pictures.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Model servers") {
                        HStack {
                            Text(local.serverRunning || local.mlxModel != nil ? "Running" : "Start when needed").foregroundStyle(.secondary)
                            if local.serverRunning || local.mlxModel != nil { Button("Stop") { local.stopServer() } }
                        }
                    }
                } header: { Text("Servers") } footer: {
                    Text("Models in GGUF form run on Lamp's own server; MLX models run on mlx-lm, which Lamp installs when one needs it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(height: listHeight)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 560)
        .task { local.refresh() }
    }

    private func installedRow(_ model: InstalledModel) -> some View {
        // A decision model answers apps' decisions and can't build: its Use chooses it for decisions.
        let decides = LocalModels.isDecisionModel(model.id)
        _ = decisionModel   // read so In use follows Use for Decisions
        let inUse = decides ? AppAI.decisionRoute(for: nil)?.provider == "local"
                            : Builder.engine == .pi && Builder.piProvider == Builder.localProvider && Builder.piModel == model.id
        let needsMLX = model.format == .mlx && LocalModels.mlxServerPath == nil
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(model.name).font(.headline)
                    Text(model.format == .mlx ? "MLX" : "GGUF").font(.caption2).padding(.horizontal, 5)
                        .background(.quaternary, in: Capsule())
                    if inUse { Text("In use").font(.caption).padding(.horizontal, 6).background(.green.opacity(0.2), in: Capsule()) }
                }
                Text("\(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file)) · \(model.source)\(model.vision ? " · sees images" : "")")
                    .font(.caption).foregroundStyle(.secondary)
                if needsMLX { Text("Needs a one-time install before it can run.").font(.caption).foregroundStyle(.orange) }
                if needsMLX, let error = tools.errors[.mlx] { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Spacer()
            if needsMLX {
                if tools.installing.contains(.mlx) { ProgressView().controlSize(.small) }
                else { Button("Install") { installMLX() } }
            } else if !inUse {
                if decides {
                    Button("Use for Decisions") {
                        if let local = AppAI.decisionModels.first(where: { $0.provider == "local" }) { decisionModel = local.id }
                    }
                } else {
                    Button("Use") { use(model.id) }
                }
            }
            if model.deletable { Button("Delete", role: .destructive) { local.delete(model.id) } }
        }
    }

    private func downloadRow(_ spec: LocalModelSpec) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.name).font(.headline)
                Text(spec.blurb).font(.caption).foregroundStyle(.secondary)
                let tight = spec.minRAMGB > LocalModels.ramGB
                Text(String(format: "%.1f GB download · needs %d GB memory%@", spec.sizeGB, spec.minRAMGB,
                            tight ? " (more than this Mac has)" : ""))
                    .font(.caption).foregroundStyle(tight ? .orange : .secondary)
                if let error = local.errors[spec.id] { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Spacer()
            if let progress = local.progress[spec.id] {
                ProgressView(value: progress).frame(width: 90)
                Button("Cancel") { local.cancel(spec.id) }
            } else {
                Button("Download") { local.download(spec) }
            }
        }
    }

    private func imageRow(_ spec: ImageModelSpec) -> some View {
        let installed = ImageModels.isInstalled(spec)
        let inUse = installed && images.chosen?.id == spec.id
        let tight = spec.minRAMGB > LocalModels.ramGB
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(spec.name).font(.headline)
                    if inUse { Text("In use").font(.caption).padding(.horizontal, 6).background(.green.opacity(0.2), in: Capsule()) }
                }
                Text(spec.blurb).font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.1f GB · needs %d GB memory%@", spec.sizeGB, spec.minRAMGB, tight ? " (more than this Mac has)" : ""))
                    .font(.caption).foregroundStyle(tight ? .orange : .secondary)
                if let error = local.errors["image:" + spec.id] { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Spacer()
            if let progress = local.progress["image:" + spec.id] {
                ProgressView(value: progress).frame(width: 90)
                Button("Cancel") { local.cancel("image:" + spec.id) }
            } else if installed {
                if !inUse { Button("Use") { images.choose(spec) } }
                Button("Delete", role: .destructive) { images.delete(spec) }
            } else {
                Button("Download") { images.download(spec) }
            }
        }
    }

    /// What MLX models run on. Afterwards the model can build, so the setup check is run again.
    private func installMLX() {
        Task {
            await tools.install(.mlx)
            await store.recheckSetup()
        }
    }

    private func use(_ id: String) {
        Builder.engine = .pi
        Builder.piProvider = Builder.localProvider
        Builder.piModel = id
        local.objectWillChange.send()
        Task { await store.recheckSetup() }
    }

    private func add() {
        adding = true
        addError = nil
        Task {
            defer { adding = false }
            do {
                let spec = try await local.spec(forRepo: repo)
                if !custom.contains(spec) && !LocalModels.catalog.contains(where: { $0.repo == spec.repo }) { custom.append(spec) }
                repo = ""
                local.download(spec)
            } catch {
                addError = error.localizedDescription
            }
        }
    }
}

