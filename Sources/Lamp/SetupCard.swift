import SwiftUI

/// Offers a way to set up a kind of AI where it's first wanted: in the chat of the app that wanted it, put
/// there by Lamp when an app hit something nothing here can do, or by the agent with `offer_setup`. Built
/// like the build card above it in the chat (an icon, a headline and a status line, then rows), and
/// what it offers comes from `AppAI.resolve`, as Settings' does, so the two always agree. Once that capability
/// is set up (here or in Settings) it folds down to its header, saying what answers now.
struct SetupCard: View {
    let offer: SetupOffer
    let reason: String
    /// The folder of the app whose chat this is.
    let dir: URL
    @ObservedObject private var local = LocalModels.shared
    @ObservedObject private var images = ImageModels.shared
    @State private var revision = 0
    @State private var declined = false

    private var project: LampProject? { Store.shared.projects.first { $0.dir == dir } }

    var body: some View {
        let _ = revision
        let resolution = AppAI.resolve(offer.capability, for: project, in: offer.context)
        // An icon's card is also answered by the person choosing to draw icons themselves.
        let byHand = resolution.provider == Icons.byHand
        let done = resolution.tier == .best
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: CardColumn.gap) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    status(resolution, done: done, byHand: byHand).font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                // Answered by drawing icons by hand, the card is where this app's is drawn, while it's plain.
                if byHand, let project, let spec = Icons.load(project), Icons.cachedArt(project, spec: spec) == nil {
                    Button("Draw Icon…") { Store.shared.iconFromPlayground(project) }
                        .controlSize(.small)
                }
                if !done && !declined {
                    Button("Not Now") {
                        if let project { offer.decline(in: project) }
                        withAnimation { declined = true }
                    }
                    .controlSize(.small)
                }
            }
            .padding(14)
            if !done && !declined {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    UpgradeList(upgrades: resolution.upgrades) { revision += 1 }
                    // Something answers already, just not as well: say what, so nothing looks broken meanwhile.
                    if resolution.tier == .works, let answer = resolution.answer {
                        Text("For now it works through \(answer); the options above work better.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, CardColumn.indent(compact: false))
                    }
                }
                .padding(14)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .animation(.easeInOut(duration: 0.35), value: done)
        .onAppear {
            revision += 1
            declined = project.map(offer.declined(in:)) ?? false
        }
        // Keys, the choices in Settings and an app's own choices all change what a capability resolves to.
        .onReceive(NotificationCenter.default.publisher(for: KeyStore.changed)) { _ in revision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: AppModels.changed)) { _ in revision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in revision += 1 }
        // A drawn icon takes Draw Icon… off the card.
        .onReceive(Store.shared.$icons) { _ in revision += 1 }
    }

    /// What's being offered, on a tile the size of the build card's app icon. Not the app's own icon: it's
    /// Lamp asking, not the app.
    private var badge: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Image(systemName: offer.context == .phoneAway ? "iphone.radiowaves.left.and.right" : offer.capability.symbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(shape.fill(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor],
                                                  startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(.black.opacity(0.08)))
            .frame(width: CardColumn.icon, height: CardColumn.icon)
    }

    private var title: String {
        if offer.context == .phoneAway { return "Use AI on your phone, away from this Mac" }
        return switch offer.capability {
        case .text: "Use AI in your apps"
        case .decisions: "Let your apps make quick judgments"
        case .pictures: "Make pictures with AI"
        }
    }

    private func doneText(_ answer: String) -> String {
        if offer.context == .phoneAway { return "All set. Away from this Mac, your phone's apps now use your OpenRouter key." }
        return switch offer.capability {
        case .text: "All set. Your apps' AI now runs on \(answer)."
        case .decisions: "All set. Your apps' judgments are now made by \(answer)."
        case .pictures: "All set. Pictures are now made by \(answer)."
        }
    }

    /// Why it's offered; once it's set up, what answers now; after Not Now, where to find it later.
    @ViewBuilder
    private func status(_ resolution: Resolution, done: Bool, byHand: Bool) -> some View {
        if done {
            Label {
                Text(byHand ? "All set. You draw each app's icon with Image Playground." : doneText(resolution.answer ?? ""))
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        } else if declined {
            Text("No problem. You can set this up any time in Lamp's Settings, under AI Providers.")
        } else {
            Text(reason)
        }
    }
}

/// What would make a capability better, best first, a row each: what it is, a line on what it costs or
/// gives, and the button that does it. The same rows in the chat's card and in Settings. In the card a key
/// is typed in place, and one OpenRouter couldn't be asked about isn't saved, since the person can wait for
/// the answer; in Settings (`compact`) a key is added in its provider's sheet, where it can be saved
/// unchecked, and several capabilities wanting the same key share that one sheet.
struct UpgradeList: View {
    let upgrades: [Upgrade]
    var compact = false
    var onChange: () -> Void = {}

    var body: some View {
        let shown = upgrades.filter(UpgradeView.isOffered)
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            ForEach(shown) { upgrade in
                UpgradeView(upgrade: upgrade, compact: compact, onChange: onChange)
            }
        }
    }
}

/// One way to make a capability better: a key, a download or a sign-in.
struct UpgradeView: View {
    let upgrade: Upgrade
    let compact: Bool
    let onChange: () -> Void

    /// Some can't be done on this Mac: a picture model that needs more memory than it has.
    static func isOffered(_ upgrade: Upgrade) -> Bool {
        switch upgrade {
        case .pictureModel:
            guard let spec = ImageModels.catalog.first else { return false }
            return Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 >= Double(spec.minRAMGB)
        case .decisionModel: return LocalModels.decisionCatalog.first != nil
        case .key(let provider): return Provider.keyProvider(provider) != nil
        case .signIn: return true
        case .drawIcons: return Icons.playgroundAvailable
        }
    }

    var body: some View {
        switch upgrade {
        case .key(let id):
            if let provider = Provider.keyProvider(id) { KeyUpgrade(provider: provider, compact: compact, onChange: onChange) }
        case .pictureModel:
            PictureModelUpgrade(compact: compact, onChange: onChange)
        case .decisionModel:
            DecisionModelUpgrade(compact: compact, onChange: onChange)
        case .signIn(let engine):
            SignInUpgrade(engine: engine, compact: compact, onChange: onChange)
        case .drawIcons:
            DrawIconsUpgrade(compact: compact)
        }
    }
}

/// The card's columns: its rows' symbols sit in a column as wide as the header's tile, against its right
/// edge, so every line of text in the card starts where the headline does.
private enum CardColumn {
    static let icon: CGFloat = 44
    static let gap: CGFloat = 12
    /// Where text under a row's title starts.
    static func indent(compact: Bool) -> CGFloat { compact ? 28 : icon + gap }
}

/// A row of an upgrade list: a symbol, what it is and a line about it, and what to press.
private struct OptionRow<Accessory: View>: View {
    let symbol: String
    let title: String
    let detail: String
    var compact = false
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 10 : CardColumn.gap) {
            Image(systemName: symbol)
                .font(compact ? .body : .title3)
                .foregroundStyle(.secondary)
                .frame(width: compact ? 18 : CardColumn.icon, alignment: compact ? .center : .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(compact ? .callout : .body)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory().controlSize(.small)
        }
    }
}

private struct KeyUpgrade: View {
    let provider: PiProvider
    let compact: Bool
    let onChange: () -> Void
    @State private var key = ""
    @State private var open = false
    @FocusState private var focused: Bool
    @StateObject private var check = KeyCheck()
    @Environment(\.openSettings) private var openSettings
    @AppStorage("settingsTab") private var settingsTab = "building"
    @AppStorage("settingsSheet") private var settingsSheet = ""

    /// Settings says it in a line; the chat's card explains, since it's often the first the person hears of it.
    private var detail: String {
        switch (provider.id, compact) {
        case ("openrouter", true): "One key for the best text, pictures and decisions. Pay as you go."
        case ("openrouter", false):
            "OpenRouter is one account for many AI models. Create a key on its website and paste it here; you pay only for what your apps use, usually cents."
        case ("typesafe", true): "Jev, made for fast, reliable judgments."
        case ("typesafe", false): "TypeSafe makes Jev, a model built for quick, reliable judgments. Create a key on its website and paste it here."
        case ("openai", _): "OpenAI's Decisions API, with a key from your OpenAI account."
        default: "Use your \(provider.name) account."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OptionRow(symbol: "key.horizontal", title: "Add \(AppAI.keyPhrase(provider.id))", detail: detail, compact: compact) {
                if compact {
                    Button("Add Key…") {
                        settingsSheet = provider.id
                        settingsTab = "providers"
                        openSettings()
                    }
                } else if !open {
                    Button("Add Key…") { open = true; focused = true }
                }
            }
            if open && !compact {
                HStack(spacing: 8) {
                    SecureField("Paste your key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit(save)
                        .onChange(of: key) { check.edited() }
                    if check.checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Cancel") { open = false; key = ""; check.edited() }
                        Button("Save", action: save)
                            .keyboardShortcut(.defaultAction)
                            .disabled(key.trimmed.isEmpty)
                    }
                }
                .controlSize(.small)
                .padding(.leading, CardColumn.indent(compact: compact))
                HStack(spacing: 4) {
                    if let problem = check.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No key yet?").foregroundStyle(.secondary)
                        Link("Get one from \(provider.name)", destination: URL(string: provider.keyURL)!)
                    }
                }
                .font(.caption)
                .padding(.leading, CardColumn.indent(compact: compact))
            }
        }
    }

    private func save() {
        check.save(key, for: provider, strict: true) {
            key = ""
            open = false
            Task { await Store.shared.recheckSetup() }
            onChange()
        }
    }
}

private struct PictureModelUpgrade: View {
    let compact: Bool
    let onChange: () -> Void
    @ObservedObject private var local = LocalModels.shared
    @ObservedObject private var tools = PythonTools.shared

    var body: some View {
        if let spec = ImageModels.catalog.first {
            OptionRow(symbol: "desktopcomputer", title: compact ? "Make them on this Mac" : "Download a picture model to this Mac",
                      detail: compact ? String(format: "Free and private, with %@. A %.1f GB download.", spec.name, spec.sizeGB)
                                      : String(format: "Pictures are made right here, free and private, with nothing sent online. %@ is a %.1f GB download and needs a Mac with %d GB of memory or more.",
                                               spec.name, spec.sizeGB, spec.minRAMGB),
                      compact: compact) {
                if let progress = local.progress["image:" + spec.id] {
                    ProgressView(value: progress).frame(width: 80).onDisappear(perform: onChange)
                } else if tools.installing.contains(.mflux) {
                    ProgressView()
                } else {
                    Button("Download") {
                        Task {
                            if !ImageModels.hasMflux { await tools.install(.mflux) }
                            if ImageModels.hasMflux { ImageModels.shared.download(spec) }
                        }
                    }
                }
            }
            if let error = tools.errors[.mflux] {
                Label(error, systemImage: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                    .font(.caption).padding(.leading, CardColumn.indent(compact: compact))
            }
        }
    }
}

private struct DecisionModelUpgrade: View {
    let compact: Bool
    let onChange: () -> Void
    @ObservedObject private var local = LocalModels.shared

    var body: some View {
        if let spec = LocalModels.decisionCatalog.first {
            OptionRow(symbol: "desktopcomputer", title: compact ? "Make them on this Mac" : "Download a judgment model to this Mac",
                      detail: compact ? String(format: "Free and private, with %@. A %.1f GB download.", spec.name, spec.sizeGB)
                                      : String(format: "Judgments are made right here, free and private, with nothing sent online. %@ is a %.1f GB download.",
                                               spec.name, spec.sizeGB),
                      compact: compact) {
                if let progress = local.progress[spec.id] {
                    ProgressView(value: progress).frame(width: 80).onDisappear(perform: onChange)
                } else {
                    Button("Download") { local.download(spec) }
                }
            }
        }
    }
}

private struct SignInUpgrade: View {
    let engine: Engine
    let compact: Bool
    let onChange: () -> Void
    @State private var working = false

    var body: some View {
        OptionRow(symbol: "person.crop.circle", title: "Sign in to \(engine.title)",
                  detail: compact ? "Use the plan you already pay for." : "Your apps can use AI through the \(engine.title) plan you already have.",
                  compact: compact) {
            if working {
                ProgressView()
            } else {
                Button("Sign In…") {
                    working = true
                    Task {
                        _ = await EngineSignIn.signIn(engine)
                        await Store.shared.recheckSetup()
                        working = false
                        onChange()
                    }
                }
            }
        }
    }
}

/// Drawing icons by hand, one of the ways to get icon artwork where nothing can draw it (`Upgrade.drawIcons`,
/// which `AppAI.resolve` lists for `.icon` alone): on the card about an app's icon and under Not Ready in
/// Settings → Building. It's a choice for every app's icon, made once.
private struct DrawIconsUpgrade: View {
    let compact: Bool

    var body: some View {
        OptionRow(symbol: "paintbrush.pointed", title: "Draw icons yourself",
                  detail: "Free, with Image Playground. You pick each app's picture.", compact: compact) {
            Button("Use for Icons") { Icons.iconChoice = Icons.byHand }
        }
    }
}

/// The line in the chat that offers to draw an app's icon, for someone who chose to draw icons themselves:
/// what's so, and the button that opens Image Playground. It's shown only while it has something to offer
/// (`Icons.awaitsDrawing`).
struct DrawIconLine: View {
    let project: LampProject

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "paintbrush.pointed").foregroundStyle(.secondary)
            Text("\(project.name) has a plain icon for now.").foregroundStyle(.secondary)
            Button("Draw Icon…") { Store.shared.iconFromPlayground(project) }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What Settings says under a capability's picker when it isn't answered the best way it could be: why,
/// and the same upgrades the chat's card offers.
struct CapabilityNote: View {
    let capability: Capability
    var project: LampProject? = nil
    var context: AIContext = .mac
    @ObservedObject private var local = LocalModels.shared
    @State private var revision = 0

    var body: some View {
        let _ = revision
        let resolution = AppAI.resolve(capability, for: project, in: context)
        if resolution.tier != .best {
            VStack(alignment: .leading, spacing: 6) {
                // Gray: in Settings the Not Ready badge beside the choice is the only orange.
                if let note = resolution.explanation {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                UpgradeList(upgrades: resolution.upgrades, compact: true) { revision += 1 }
            }
            // Keys, the choices in Settings and an app's own choices all change what a capability resolves to.
        .onReceive(NotificationCenter.default.publisher(for: KeyStore.changed)) { _ in revision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: AppModels.changed)) { _ in revision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in revision += 1 }
        }
    }
}
