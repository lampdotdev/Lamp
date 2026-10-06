import SwiftUI
import AppKit

/// The first-launch welcome: what Forge is, the user's first idea, getting set up, then straight into
/// building it. It lives in the main window, dressed up without the usual window chrome, and the window
/// grows into Forge itself at the end.
enum Onboarding {
    static let key = "onboarded"

    /// People who used Forge before the welcome existed have apps already: they skip it.
    static func settle(hasApps: Bool) {
        if UserDefaults.standard.object(forKey: key) == nil && hasApps {
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    static var isDone: Bool { UserDefaults.standard.bool(forKey: key) }

    static let size = CGSize(width: 1080, height: 760)
    /// The smallest the welcome's window gets; everything still fits.
    static let minimumSize = CGSize(width: 900, height: 660)
    /// The window Forge opens into after the welcome.
    static let appSize = CGSize(width: 1180, height: 800)
}

private enum Step: Int, CaseIterable {
    case hello, idea, setup, ready
}

/// Forge's colors while the brand is still settling: the ember of its icon, on a bright, warm ground.
private enum Palette {
    static let ground = Color(red: 0.992, green: 0.988, blue: 0.980)
    static let ember = Color(red: 1.0, green: 0.48, blue: 0.13)
    static let emberDeep = Color(red: 0.93, green: 0.33, blue: 0.08)
    static let ink = Color(red: 0.11, green: 0.10, blue: 0.10)
    static let card = Color.white.opacity(0.72)
}

struct OnboardingView: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Onboarding.key) private var onboarded = false
    /// `-onboardingStep 2` on the command line opens on a later step, for checking the welcome.
    @State private var step = Step(rawValue: UserDefaults.standard.integer(forKey: "onboardingStep")) ?? .hello
    @State private var forward = true
    @State private var prompt = ""
    @State private var leaving = false
    @State private var window: NSWindow?

    var body: some View {
        ZStack {
            ZStack {
                switch step {
                case .hello: HelloStep { go(to: .idea) }
                case .idea: IdeaStep(prompt: $prompt, back: { go(to: .hello) }) { go(to: .setup) }
                case .setup: SetupStep(back: { go(to: .idea) }) { go(to: .ready) }
                case .ready: ReadyStep(prompt: prompt, back: { go(to: .setup) }, start: finish)
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .stage(from: forward ? 1 : -1), removal: .stage(from: forward ? -1 : 1)))
            .opacity(leaving ? 0 : 1)
            .scaleEffect(leaving ? 1.03 : 1)

            Dots(current: step)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 22)
                .opacity(step == .hello || leaving ? 0 : 1)
        }
        .frame(minWidth: Onboarding.minimumSize.width, maxWidth: .infinity,
               minHeight: Onboarding.minimumSize.height, maxHeight: .infinity)
        .background(Palette.ground)
        .clipped()
        .ignoresSafeArea()
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationTitle("")
        .environment(\.colorScheme, .light)
        .tint(Palette.ember)
        .background(WindowReader { window = $0 })
        .onChange(of: window) { if let window { Chrome.hide(window) } }
    }

    private func go(to next: Step) {
        forward = next.rawValue > step.rawValue
        withAnimation(.spring(response: 0.6, dampingFraction: 0.88)) { step = next }
    }

    /// Fades the welcome out, grows the window into Forge's, and starts the first app on the user's idea.
    private func finish() {
        withAnimation(.easeIn(duration: 0.3)) { leaving = true }
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            let idea = prompt.trimmed
            let window = window
            withAnimation(.easeOut(duration: 0.4)) { onboarded = true }
            // Once Forge's own view is in, so the welcome's fixed size doesn't hold the window back.
            try? await Task.sleep(for: .seconds(0.05))
            if let window { Chrome.restore(window, to: Onboarding.appSize) }
            guard !idea.isEmpty else { return }
            store.create()
            if let project = store.selected { store.send(idea, to: project) }
        }
    }
}

// MARK: - Steps

/// 1. What Forge is, with a parade of apps people make.
private struct HelloStep: View {
    let next: () -> Void
    @State private var shown = false

    var body: some View {
        // One cluster in the middle, with fixed gaps: resizing the window only changes the margins around it.
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 52, height: 52)
                .shadow(color: Palette.emberDeep.opacity(0.25), radius: 12, y: 6)
                .scaleEffect(shown ? 1 : 0.8)
                .opacity(shown ? 1 : 0)
            Text("What will you make?")
                .font(.system(size: 54, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(Palette.ink)
                .padding(.top, 22)
                .reveal(shown, delay: 0.1)
            Text("Forge turns your ideas into your very own native Mac apps.")
                .font(.system(size: 19))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .reveal(shown, delay: 0.2)
            // Taller than the rows need, so a hovered icon (bigger, with its shadow) has room; the extra
            // height comes out of the gaps above and below.
            Parade()
                .frame(height: 240)
                .padding(.top, 30)
                .reveal(shown, delay: 0.35)
            BigButton(title: "Get Started", action: next)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 30)
                .reveal(shown, delay: 0.5)
            Spacer(minLength: 24)
        }
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { shown = true } }
    }
}

/// Two rows of app icons drifting past in opposite directions, on the front of a huge invisible drum: biggest
/// in the middle, smaller and turned away towards the sides, and never round the back.
private struct Parade: View {
    private static let rows = [Array(Ideas.pool.prefix(24)), Array(Ideas.pool.dropFirst(24))]
    /// From one icon to the next, measured along the drum.
    private static let pitch: CGFloat = 132
    /// From one row's middle to the other's.
    private static let rowGap: CGFloat = 112
    /// Points per second.
    private static let speed = 14.0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // The drum is twice as wide as the window, seen from close enough that the sides shrink a little
            // and bunch up, but never so much that names run into each other.
            let radius = max(size.width, Onboarding.minimumSize.width) * 2
            let camera = radius * 0.25
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<2, id: \.self) { row in
                        let ideas = Self.rows[row]
                        let loop = CGFloat(ideas.count) * Self.pitch
                        let travel = CGFloat((time * (row == 0 ? -Self.speed : Self.speed)).truncatingRemainder(dividingBy: Double(loop)))
                        ForEach(ideas.indices, id: \.self) { index in
                            // Where along the drum, from the front, wrapped so each icon is shown once.
                            let along = Self.wrap(CGFloat(index) * Self.pitch + travel, loop)
                            let angle = along / radius
                            if abs(angle) < .pi / 2 {
                                let depth = radius * (1 - cos(angle))
                                let scale = 1.1 * camera / (camera + depth)
                                ParadeItem(idea: ideas[index])
                                    .rotation3DEffect(.radians(Double(angle)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                                    .scaleEffect(scale)
                                    .position(x: size.width / 2 + radius * sin(angle) * camera / (camera + depth),
                                              y: size.height / 2 + (row == 0 ? -1 : 1) * Self.rowGap / 2 * scale)
                                    .zIndex(Double(cos(angle)))
                            }
                        }
                    }
                }
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                                     .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
    }

    /// Into -loop/2 ..< loop/2.
    private static func wrap(_ value: CGFloat, _ loop: CGFloat) -> CGFloat {
        var wrapped = value.truncatingRemainder(dividingBy: loop)
        if wrapped < -loop / 2 { wrapped += loop }
        if wrapped >= loop / 2 { wrapped -= loop }
        return wrapped
    }
}

private struct ParadeItem: View {
    let idea: Idea

    var body: some View {
        VStack(spacing: 8) {
            HoverIcon(idea: idea, size: 46)
            Text(idea.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 92)
    }
}

private struct HoverIcon: View {
    let idea: Idea
    let size: CGFloat
    @State private var hovering = false

    var body: some View {
        IdeaIcon(symbol: idea.symbol, hue: idea.hue, size: size, lit: hovering)
            .scaleEffect(hovering ? 1.08 : 1)
            .onHover { over in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hovering = over } }
    }
}

/// 2. The first idea: in their own words, or from a tile.
private struct IdeaStep: View {
    @Binding var prompt: String
    let back: () -> Void
    let next: () -> Void
    @StateObject private var dictation = Dictation()
    @State private var page = 0
    @State private var ideas = Ideas.page(0)
    @State private var invented: [Idea]?
    @State private var inventing = false
    @State private var seen = Set(Ideas.page(0).map(\.title))
    @State private var chosen: String?
    @State private var flip = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Heading(title: "What should your first app do?",
                    detail: "Say it in your own words, or start from an idea and make it yours.")
                .padding(.top, 52)

            HStack(alignment: .top, spacing: 10) {
                TextField("", text: $prompt,
                          prompt: Text("An app that…").foregroundStyle(.tertiary), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .lineSpacing(3)
                    .lineLimit(3...5)
                    .focused($focused)
                    .onChange(of: prompt) { if prompt != ideas.first(where: { $0.id == chosen })?.prompt { chosen = nil } }
                Button(action: toggleDictation) {
                    Image(systemName: dictation.isListening ? "waveform" : "mic")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(dictation.isListening ? Palette.ember : .secondary)
                        .symbolEffect(.variableColor.iterative, isActive: dictation.isListening)
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(dictation.isListening ? 0.06 : 0), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(dictation.isListening ? "Stop dictating" : "Describe it out loud")
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .frame(width: 720)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(focused ? Palette.ember.opacity(0.55) : .black.opacity(0.08), lineWidth: focused ? 1.5 : 1))
            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
            .padding(.top, 28)

            HStack {
                Text("Need an idea?").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: more) {
                    HStack(spacing: 5) {
                        Image(systemName: invented != nil ? "sparkles" : "arrow.clockwise")
                        Text("Show me others")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.emberDeep)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 720)
            .padding(.top, 26)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(Array(ideas.enumerated()), id: \.element.id) { index, idea in
                    IdeaTile(idea: idea, selected: chosen == idea.id) { choose(idea) }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92)).animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.04)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))))
                }
            }
            .frame(width: 720)
            .padding(.top, 10)

            Spacer()
            Footer(back: back) {
                BigButton(title: "Continue", action: next).disabled(prompt.trimmed.isEmpty)
            } aside: {
                if prompt.trimmed.isEmpty {
                    Button("Skip for now", action: next).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            prefetch()
            // After the step has slid in: focus can't land while the old step still holds it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
        }
        .onDisappear { dictation.cancel() }
    }

    private func choose(_ idea: Idea) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { chosen = idea.id }
        prompt = idea.prompt
        focused = true
    }

    /// The next six: made up on this Mac when it can, otherwise the next page of the built-in ideas.
    private func more() {
        let next: [Idea]
        if let invented {
            next = invented
            self.invented = nil
        } else {
            page += 1
            next = Ideas.page(page)
        }
        seen.formUnion(next.map(\.title))
        withAnimation { ideas = next }
        prefetch()
    }

    private func prefetch() {
        guard Ideas.canInvent, invented == nil, !inventing else { return }
        inventing = true
        Task {
            let avoiding = Array(seen) + Ideas.pool.map(\.title)
            invented = await Ideas.invent(avoiding: avoiding)
            inventing = false
        }
    }

    private func toggleDictation() {
        if dictation.isListening { return dictation.stop() }
        let typed = prompt.trimmed
        let separator = typed.isEmpty ? "" : " "
        Task { await dictation.start { prompt = typed + separator + $0 } }
    }
}

private struct IdeaTile: View {
    let idea: Idea
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                IdeaIcon(symbol: idea.symbol, hue: idea.hue, size: 36, lit: hovering || selected)
                VStack(alignment: .leading, spacing: 3) {
                    Text(idea.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(idea.blurb).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(selected ? Color.white : (hovering ? Color.white.opacity(0.9) : Palette.card),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Palette.ember : .black.opacity(0.06), lineWidth: selected ? 1.5 : 1))
            .shadow(color: .black.opacity(hovering || selected ? 0.08 : 0.03), radius: hovering ? 12 : 6, y: hovering ? 6 : 3)
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { over in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hovering = over } }
    }
}

/// 3. Apple's tools, and what builds the apps.
private struct SetupStep: View {
    @EnvironmentObject private var store: Store
    let back: () -> Void
    let next: () -> Void
    @AppStorage("engine") private var engine = Engine.pi.rawValue
    @AppStorage("piProvider") private var piProvider = "openrouter"
    @State private var choice: Builder.Choice?
    @State private var signedIn: [Engine: Bool] = [:]
    @State private var signingIn: Engine?

    var body: some View {
        VStack(spacing: 0) {
            Heading(title: "Let's get Forge ready",
                    detail: "Two quick things, and they can happen at the same time.")
                .padding(.top, 40)

            VStack(spacing: 12) {
                ToolsCard()
                BuilderCard(choice: $choice, signedIn: $signedIn, signingIn: $signingIn)
            }
            .frame(width: 680)
            .padding(.top, 22)

            Spacer()
            Footer(back: back) {
                BigButton(title: "Continue", action: next).disabled(!ready)
            } aside: {
                EmptyView()
            }
        }
        .onAppear {
            if !store.setup.hasBuildTools && !store.setup.installRequested { store.requestBuildTools() }
            choice = Builder.Choice.current(engine: engine, piProvider: piProvider, ready: store.setup.hasBuilder)
        }
        .task { await refreshSignIns() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from installing Claude or ChatGPT, signing in, or Settings.
            Task {
                await store.recheckSetup()
                await refreshSignIns()
            }
        }
    }

    /// Ready once something can build. Claude and ChatGPT also need to be signed in.
    private var ready: Bool {
        guard store.setup.hasBuilder, let choice, choice.matches(engine: engine, piProvider: piProvider) else { return false }
        switch choice {
        case .claude: return signedIn[.claude] == true
        case .chatGPT: return signedIn[.codex] == true
        default: return true
        }
    }

    private func refreshSignIns() async {
        for engine in [Engine.claude, .codex] where ToolLocator.path(for: engine) != nil && signingIn != engine {
            signedIn[engine] = await EngineSignIn.isSignedIn(engine)
        }
    }
}

extension Builder {
    /// What the welcome offers to build apps with.
    enum Choice: Hashable {
        case claude, chatGPT, openRouter, onThisMac, another

        var isForge: Bool { self != .claude && self != .chatGPT }

        static func current(engine: String, piProvider: String, ready: Bool) -> Choice? {
            guard ready else { return nil }
            switch Engine(rawValue: engine) {
            case .claude: return .claude
            case .codex: return .chatGPT
            default:
                switch piProvider {
                case "openrouter": return .openRouter
                case Builder.localProvider, "ext-ollama", "ext-lmstudio": return .onThisMac
                default: return .another
                }
            }
        }

        func matches(engine: String, piProvider: String) -> Bool {
            switch self {
            case .claude: return engine == Engine.claude.rawValue
            case .chatGPT: return engine == Engine.codex.rawValue
            case .openRouter: return engine == Engine.pi.rawValue && piProvider == "openrouter"
            case .onThisMac, .another: return engine == Engine.pi.rawValue && piProvider != "openrouter"
            }
        }
    }
}

private struct ToolsCard: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                IdeaIcon(symbol: "hammer.fill", hue: 0.6, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple's app-building tools").font(.system(size: 15, weight: .semibold))
                    Text(LocalizedStringKey(detail))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if store.setup.hasBuildTools {
                    Done()
                } else if store.setup.installRequested {
                    VStack(alignment: .trailing, spacing: 6) {
                        ProgressView().controlSize(.small)
                        Button("Show Installer", action: SetupCheck.installBuildTools)
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.emberDeep)
                    }
                } else {
                    Button("Install") { store.requestBuildTools() }
                }
            }
        }
    }

    private var detail: String {
        if store.setup.hasBuildTools { return "Installed. Free from Apple, no account needed." }
        if store.setup.installRequested {
            return "In Apple's window, click **Install**, then **Agree**. It takes 5–10 minutes, and you can carry on meanwhile."
        }
        return "Free from Apple, and no developer account needed."
    }
}

private struct BuilderCard: View {
    @EnvironmentObject private var store: Store
    @Binding var choice: Builder.Choice?
    @Binding var signedIn: [Engine: Bool]
    @Binding var signingIn: Engine?
    @AppStorage("engine") private var engine = Engine.pi.rawValue
    @AppStorage("piProvider") private var piProvider = "openrouter"
    @AppStorage("settingsTab") private var settingsTab = "building"
    @AppStorage("settingsSheet") private var settingsSheet = ""
    @Environment(\.openSettings) private var openSettings
    @State private var key = ""
    @State private var checkingKey = false
    @State private var problem: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose what makes your apps").font(.system(size: 15, weight: .semibold))
                    Text("Use an AI account you already have, or Forge's own. You can change this any time.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Option(selected: choice == .claude, title: "Claude", detail: "Your Claude account") {
                        ProviderLogo(id: "anthropic", size: 30)
                    } action: { pick(.claude) }
                    Option(selected: choice == .chatGPT, title: "ChatGPT", detail: "Your ChatGPT account") {
                        ProviderLogo(id: "openai", size: 30)
                    } action: { pick(.chatGPT) }
                    Option(selected: choice?.isForge == true, title: "Forge", detail: "Any AI, or one on this Mac") {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                    } action: { pick(choice?.isForge == true ? choice! : .openRouter) }
                }
                if let choice {
                    detail(for: choice)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                        .id(choice)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: choice)
        }
    }

    private func pick(_ new: Builder.Choice) {
        problem = nil
        choice = new
    }

    @ViewBuilder
    private func detail(for choice: Builder.Choice) -> some View {
        switch choice {
        case .claude: account(.claude, app: "Claude", download: "https://claude.ai/download")
        case .chatGPT: account(.codex, app: "ChatGPT", download: "https://openai.com/chatgpt/download/")
        default: forge(choice)
        }
    }

    /// Claude or ChatGPT: get the app if it's missing, then sign in.
    @ViewBuilder
    private func account(_ which: Engine, app: String, download: String) -> some View {
        let installed = ToolLocator.path(for: which) != nil
        let using = engine == which.rawValue
        HStack(spacing: 10) {
            if !installed {
                Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                Text("\(app) isn't on this Mac yet. Get the \(app) app, open it once, then come back here.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Link("Get \(app)", destination: URL(string: download)!)
                    .font(.system(size: 13, weight: .medium))
            } else if using && signedIn[which] == true {
                Done()
                Text("\(app) will make your apps.").font(.system(size: 13, weight: .medium))
                Spacer()
            } else if signingIn == which {
                ProgressView().controlSize(.small)
                Text("Finish signing in to \(app) in your browser…").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            } else {
                Text(problem ?? "Sign in with your \(app) account. Forge uses it to make your apps.")
                    .font(.system(size: 13)).foregroundStyle(problem == nil ? Color.secondary : Color.orange)
                Spacer()
                Button("Use \(app)") { use(which) }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func forge(_ choice: Builder.Choice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: Binding(get: { choice }, set: { pick($0) })) {
                Text("OpenRouter").tag(Builder.Choice.openRouter)
                Text("A model on this Mac").tag(Builder.Choice.onThisMac)
                Text("Another provider").tag(Builder.Choice.another)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            let using = store.setup.hasBuilder && choice.matches(engine: engine, piProvider: piProvider)
            switch choice {
            case .openRouter:
                if using {
                    HStack(spacing: 10) {
                        Done()
                        Text("Your OpenRouter key is saved.").font(.system(size: 13, weight: .medium))
                    }
                } else {
                    Text("Hundreds of AI models, paying OpenRouter only for what you use.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        SecureField("Paste your OpenRouter key", text: $key)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveKey)
                            .onChange(of: key) { problem = nil }
                        if checkingKey {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Save", action: saveKey).disabled(key.trimmed.isEmpty)
                        }
                        Link("Get a key", destination: URL(string: "https://openrouter.ai/keys")!)
                            .font(.system(size: 13, weight: .medium))
                    }
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
                    }
                }
            case .onThisMac:
                settingsRow(using: using,
                            detail: "Free and private: Forge downloads a model and runs it here. Smaller models make simpler apps.",
                            button: "Choose a Model…") { open(tab: "providers", sheet: Builder.localProvider) }
            default:
                settingsRow(using: using,
                            detail: "Anthropic, OpenAI, Google and about twenty more, with your own key.",
                            button: "Choose a Provider…") { open(tab: "building") }
            }
        }
    }

    private func settingsRow(using: Bool, detail: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            if using {
                Done()
                Text(Builder.summary).font(.system(size: 13, weight: .medium))
                Spacer()
                Button("Change…", action: action)
            } else {
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(button, action: action)
            }
        }
    }

    private func open(tab: String, sheet: String = "") {
        settingsTab = tab
        settingsSheet = sheet
        openSettings()
    }

    private func use(_ which: Engine) {
        problem = nil
        Builder.engine = which
        engine = which.rawValue
        Task {
            var ok = await EngineSignIn.isSignedIn(which) == true
            if !ok {
                signingIn = which
                ok = await EngineSignIn.signIn(which)
                signingIn = nil
                NSApp.activate()
            }
            signedIn[which] = ok
            if !ok { problem = "Signing in didn't finish. Try again." }
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
            if let found = await SetupView.checkOpenRouterKey(candidate) {
                problem = found
                return
            }
            KeyStore.setOpenRouterKey(candidate)
            key = ""
            Builder.engine = .pi
            Builder.piProvider = "openrouter"
            engine = Engine.pi.rawValue
            piProvider = "openrouter"
            await store.recheckSetup()
        }
    }
}

private struct Option<Logo: View>: View {
    let selected: Bool
    let title: String
    let detail: String
    @ViewBuilder let logo: () -> Logo
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                logo().frame(height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected || hovering ? Color.white : Color.white.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Palette.ember : .black.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { over in withAnimation(.easeOut(duration: 0.15)) { hovering = over } }
    }
}

/// 4. The send-off.
private struct ReadyStep: View {
    @EnvironmentObject private var store: Store
    let prompt: String
    let back: () -> Void
    let start: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .strokeBorder(Palette.ember.opacity(0.18 - Double(ring) * 0.05), lineWidth: 1)
                        .frame(width: 150 + CGFloat(ring) * 56, height: 150 + CGFloat(ring) * 56)
                        .scaleEffect(shown ? 1 : 0.6)
                        .opacity(shown ? 1 : 0)
                        .animation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.1 + Double(ring) * 0.08), value: shown)
                }
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 120, height: 120)
                    .shadow(color: Palette.emberDeep.opacity(0.3), radius: 30, y: 14)
                    .scaleEffect(shown ? 1 : 0.7)
                    .rotationEffect(.degrees(shown ? 0 : -12))
            }
            .frame(height: 260)
            Text("Let's get building.")
                .font(.system(size: 54, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(Palette.ink)
                .reveal(shown, delay: 0.15)
            Text(detail)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                .padding(.top, 12)
                .reveal(shown, delay: 0.25)
            if !prompt.trimmed.isEmpty {
                Text(prompt.trimmed)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.ink.opacity(0.75))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .frame(width: 560, alignment: .leading)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.06)))
                    .padding(.top, 22)
                    .reveal(shown, delay: 0.35)
            }
            Spacer(minLength: 28)
            Footer(back: back) {
                BigButton(title: prompt.trimmed.isEmpty ? "Open Forge" : "Start Building", action: start)
                    .keyboardShortcut(.defaultAction)
            } aside: {
                EmptyView()
            }
        }
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) { shown = true } }
    }

    private var detail: String {
        if prompt.trimmed.isEmpty { return "Describe an app whenever you're ready, and Forge makes it." }
        if !store.setup.hasBuildTools {
            return "Your app starts as soon as Apple's tools finish installing. Forge names it, designs its icon and opens it for you."
        }
        return "Forge names your app, designs its icon and opens it for you when it's ready. It usually takes a few minutes."
    }
}

// MARK: - Pieces

private struct Heading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 38, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Palette.ink)
            Text(detail)
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }
}

private struct Done: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(.white, .green)
            .transition(.scale.combined(with: .opacity))
    }
}

/// Back on the left, the way forward on the right.
private struct Footer<Primary: View, Aside: View>: View {
    let back: () -> Void
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let aside: () -> Aside

    var body: some View {
        HStack(spacing: 18) {
            Button(action: back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            Spacer()
            aside()
            primary()
        }
        .padding(.horizontal, 44)
        .padding(.bottom, 44)
    }
}

private struct BigButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 30).frame(height: 46)
                .background(
                    Capsule().fill(LinearGradient(colors: [Palette.ember, Palette.emberDeep], startPoint: .top, endPoint: .bottom))
                )
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Palette.emberDeep.opacity(enabled ? (hovering ? 0.4 : 0.28) : 0), radius: hovering ? 16 : 10, y: 6)
                .scaleEffect(hovering && enabled ? 1.03 : 1)
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { over in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hovering = over } }
    }
}

private struct Dots: View {
    let current: Step

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Step.allCases.dropFirst(), id: \.self) { step in
                Capsule()
                    .fill(step == current ? Palette.ember : Color.black.opacity(0.13))
                    .frame(width: step == current ? 20 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
    }
}

// MARK: - Motion

private extension AnyTransition {
    /// A step slides in from the side it's coming from, sharpening out of a blur.
    static func stage(from side: CGFloat) -> AnyTransition {
        .modifier(active: StageModifier(offset: 60 * side, blur: 14, opacity: 0),
                  identity: StageModifier(offset: 0, blur: 0, opacity: 1))
    }
}

private struct StageModifier: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.offset(x: offset).blur(radius: blur).opacity(opacity)
    }
}

private extension View {
    /// Rises into place, a beat after `delay`.
    func reveal(_ shown: Bool, delay: Double) -> some View {
        self.opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .blur(radius: shown ? 0 : 6)
            .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(delay), value: shown)
    }
}

// MARK: - Window

/// Hands back the window a view is in.
private struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { found(window) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// The welcome has no window chrome: no title, no buttons, and the whole window drags. At the end
/// the window gets its chrome back and grows into Forge's, around the same center.
private enum Chrome {
    private static var saved: (mask: NSWindow.StyleMask, transparent: Bool, title: NSWindow.TitleVisibility, movable: Bool,
                               name: String, minSize: NSSize)?

    static func hide(_ window: NSWindow) {
        guard saved == nil else { return }
        saved = (window.styleMask, window.titlebarAppearsTransparent, window.titleVisibility, window.isMovableByWindowBackground,
                 window.title, window.contentMinSize)
        window.title = ""
        window.styleMask.insert([.fullSizeContentView, .resizable])
        window.contentMinSize = Onboarding.minimumSize
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .aqua)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        let size = Onboarding.size
        window.setContentSize(size)
        window.center()
        // SwiftUI sets up the title bar again once the window is on screen; take it away again after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            window.title = ""
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            // …and lay the content out again, now that it reaches the top edge.
            window.contentView?.needsLayout = true
            window.setContentSize(size)
        }
    }

    static func restore(_ window: NSWindow, to size: CGSize) {
        guard let saved else { return }
        self.saved = nil
        window.styleMask = saved.mask.union(.resizable)
        window.contentMinSize = saved.minSize
        window.titlebarAppearsTransparent = saved.transparent
        window.titleVisibility = saved.title
        window.title = saved.name
        window.titlebarSeparatorStyle = .automatic
        window.isMovableByWindowBackground = saved.movable
        window.appearance = nil
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = false
        }
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        // Never smaller than the welcome was, if the user made it bigger.
        let width = min(max(size.width, window.frame.width), visible.width - 40)
        let height = min(max(size.height, window.frame.height), visible.height - 40)
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        var frame = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        frame.origin.x = max(visible.minX + 20, min(frame.origin.x, visible.maxX - width - 20))
        frame.origin.y = max(visible.minY + 20, min(frame.origin.y, visible.maxY - height - 20))
        window.setFrame(frame, display: true, animate: true)
    }
}
