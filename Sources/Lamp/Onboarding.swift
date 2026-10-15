import SwiftUI
import AppKit

/// The first-launch welcome: what Lamp is, the user's first idea, getting set up, then straight into
/// building it. It lives in the main window, dressed up without the usual window chrome, and the window
/// grows into Lamp itself at the end.
enum Onboarding {
    static let key = "onboarded"
    /// The first idea and how far the welcome got. Saved, so that quitting during setup, or losing the
    /// window while away at an installer or a sign-in in the browser, comes back to setup with the idea intact.
    static let ideaKey = "welcomeIdea"
    static let stepKey = "welcomeStep"
    /// What the first app is made as, kept with the idea.
    static let kindKey = "welcomeKind"
    /// When the welcome was first shown, for how long it took (`Analytics`).
    static let startedKey = "welcomeStarted"

    /// People who used Lamp before the welcome existed have apps already: they skip it.
    static func settle(hasApps: Bool) {
        if UserDefaults.standard.object(forKey: key) == nil && hasApps {
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    static var isDone: Bool { UserDefaults.standard.bool(forKey: key) }

    static let size = CGSize(width: 1080, height: 660)
    /// The window Lamp opens into after the welcome.
    static let appSize = CGSize(width: 1180, height: 800)
}

private enum Step: Int, CaseIterable {
    case hello, idea, setup

    /// Where the welcome opens: at setup if that's where it was left, otherwise from the start.
    /// `-onboardingStep 2` on the command line opens on a later step, for checking the welcome.
    static var opening: Step {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "onboardingStep") != nil { return Step(rawValue: defaults.integer(forKey: "onboardingStep")) ?? .hello }
        return defaults.integer(forKey: Onboarding.stepKey) == Step.setup.rawValue ? .setup : .hello
    }
}

/// Lamp's colors: near-black ink on a warm white page, where the porcelain lamp behind the welcome sits.
private enum Palette {
    static let ground = Color(nsColor: LampBackdrop.page)
    static let accent = Color(red: 0.2, green: 0.19, blue: 0.18)
    static let accentDeep = Color(red: 0.08, green: 0.075, blue: 0.07)
    static let ink = Color(red: 0.11, green: 0.10, blue: 0.10)
    static let card = Color.white.opacity(0.72)
}

struct OnboardingView: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Onboarding.key) private var onboarded = false
    @State private var step = Step.opening
    @State private var forward = true
    @AppStorage(Onboarding.ideaKey) private var prompt = ""
    @State private var leaving = false
    @State private var window: NSWindow?
    /// The wish that came from the site this run (`Wish`), and whether it has yet to be written into the box.
    @State private var wish: String?
    @State private var wishUnwritten = false
    @State private var dawn = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ZStack {
                switch step {
                case .hello: HelloStep { go(to: .idea) }
                case .idea: IdeaStep(prompt: $prompt, wish: wish, unwritten: $wishUnwritten, paste: { receive($0) },
                                     back: { go(to: .hello) }) { go(to: .setup) }
                case .setup: SetupStep(back: { go(to: .idea) }, start: finish)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Palette.ground
                LampBackdrop(step: step.rawValue)
                // Behind the later steps' content the lamp fades into the page, so it never competes with it.
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: Palette.ground.opacity(0.425), location: 0.24),
                                       .init(color: Palette.ground.opacity(0.425), location: 0.76), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .opacity(step == .hello ? 0 : 1)
                    .animation(.easeInOut(duration: 0.8), value: step)
                // Dawn, where the site left off when the wish appeared there: it fades into Lamp's daylight.
                LinearGradient(colors: [Color(red: 1, green: 0.74, blue: 0.5).opacity(0.62), Color(red: 1, green: 0.6, blue: 0.5).opacity(0.3)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(dawn)
            }
            .ignoresSafeArea()
        }
        .clipped()
        .ignoresSafeArea()
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationTitle("")
        .environment(\.colorScheme, .light)
        .tint(Palette.accent)
        .background(WindowReader { window = $0 })
        .onChange(of: window) { if let window { Chrome.hide(window) } }
        .onAppear {
            if UserDefaults.standard.object(forKey: Onboarding.startedKey) == nil {
                UserDefaults.standard.set(Date(), forKey: Onboarding.startedKey)
            }
            arrive(animated: false)
            Analytics.capture(.welcomeStep, ["step": "\(step)"])
        }
        .onChange(of: store.arrivedWish) { arrive(animated: true) }
        // Menus can be rebuilt at any moment, so keep Settings switched off for as long as the welcome is up.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUpdateNotification)) { _ in
            SettingsMenu.enable(false)
        }
    }

    private func go(to next: Step) {
        forward = next.rawValue > step.rawValue
        UserDefaults.standard.set(next.rawValue, forKey: Onboarding.stepKey)
        Analytics.capture(.welcomeStep, ["step": "\(next)", "back": !forward])
        withAnimation(.spring(response: 0.6, dampingFraction: 0.88)) { step = next }
    }

    /// Takes a wish from the site: one its link brought or, the first time the welcome is ever shown, one its
    /// Download button left on the clipboard. That one look is all Lamp takes by itself.
    private func arrive(animated: Bool) {
        var found = store.arrivedWish
        if found != nil { store.arrivedWish = nil }
        let defaults = UserDefaults.standard
        if found == nil, !defaults.bool(forKey: Wish.lookedKey) {
            defaults.set(true, forKey: Wish.lookedKey)
            if prompt.trimmed.isEmpty, case .wish(let text) = Wish.look() { found = text }
        }
        if let found { receive(found, animated: animated) }
    }

    /// Opens on the first-app step with the wish, with no hello in between: they have already said what they
    /// want. The words come in as the site's did, under a dawn that fades.
    private func receive(_ text: String, animated: Bool = true) {
        prompt = text
        wish = text
        wishUnwritten = true
        if step != .idea {
            if animated { go(to: .idea) } else { step = .idea }
        }
        guard !reduceMotion else { return }
        Task {
            dawn = 1
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.easeOut(duration: 3.2)) { dawn = 0 }
        }
    }

    /// Fades the welcome out, grows the window into Lamp's, and starts the first app on the user's idea.
    private func finish() {
        withAnimation(.easeIn(duration: 0.3)) { leaving = true }
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            let idea = prompt.trimmed
            let window = window
            let started = UserDefaults.standard.object(forKey: Onboarding.startedKey) as? Date
            Analytics.capture(.welcomeDone, [
                "agent": Builder.Choice.current(engine: Builder.engine.rawValue, piProvider: Builder.piProvider, ready: true)
                    .map(Analytics.agent) ?? "none",
                "has_idea": !idea.isEmpty,
                "seconds": started.map { Int(Date().timeIntervalSince($0)) } ?? -1,
            ])
            // The welcome is over: nothing to come back to.
            UserDefaults.standard.removeObject(forKey: Onboarding.ideaKey)
            UserDefaults.standard.removeObject(forKey: Onboarding.stepKey)
            UserDefaults.standard.removeObject(forKey: Onboarding.kindKey)
            UserDefaults.standard.removeObject(forKey: Onboarding.startedKey)
            withAnimation(.easeOut(duration: 0.4)) {
                onboarded = true
                store.welcomeFinished = true
            }
            SettingsMenu.enable(true)
            // Once Lamp's own view is in, so the welcome's fixed size doesn't hold the window back.
            try? await Task.sleep(for: .seconds(0.05))
            if let window { Chrome.restore(window, to: Onboarding.appSize) }
            let importing = store.openWaitingImport()
            // Skipping the idea still leaves Lamp on a new app, ready for one, unless a shared app is
            // being opened instead: that's what the person came for.
            if idea.isEmpty && importing { return }
            store.create(fromWelcome: true)
            guard let project = store.selected else { return }
            guard !idea.isEmpty else { return }
            // An iPhone or iPad app needs Xcode and a simulator first, checked as the chat's Send does, and the
            // idea is kept the same way while that runs: in the message box (so it's on disk if Lamp quits) and
            // as a pending submission (so the new app isn't discarded as unused). Cancelled, it stays there.
            let captured = Store.Draft(text: idea)
            guard let token = store.beginSubmission(project) else { return }
            store.updateDraft(captured, for: project)
            @MainActor func settle(_ sent: Bool) {
                if let current = store.current(project) {
                    store.updateDraft(store.draft(for: current).afterSubmission(captured, sent: sent), for: current)
                }
                store.endSubmission(token)
            }
            PhoneSetup.shared.perform(for: project, in: store, cancelled: { settle(false) }) { current in
                store.send(idea, to: current)
                settle(true)
            }
        }
    }
}

// MARK: - Steps

/// 1. What Lamp is, over the lamp itself.
private struct HelloStep: View {
    let next: () -> Void
    @State private var shown = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // The website's own promise, so someone who just came from it sees the same words; the question
                // is the next step's, where it can be answered.
                Text("Lamp turns your wishes\ninto selfish software.")
                    .font(.system(size: 54, weight: .bold))
                    .tracking(-1.2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.ink)
                    .reveal(shown, delay: 0.1)
                Text("Made by you, for nobody else. Tools, apps and games for your Mac, iPhone and iPad.")
                    .font(.system(size: 19))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .reveal(shown, delay: 0.2)
                BigButton(title: "Get Started", action: next)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 30)
                    .reveal(shown, delay: 0.35, rise: 8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // A moment after appearing, once the window has its size.
        .task {
            try? await Task.sleep(for: .seconds(0.15))
            shown = true
        }
    }
}

/// 2. The first idea: in their own words, or from a tile.
private struct IdeaStep: View {
    @Binding var prompt: String
    /// The wish that came from the site, if one did, and whether it still has to be written into the box.
    let wish: String?
    @Binding var unwritten: Bool
    /// The person pasted their wish with the button in the box.
    let paste: (String) -> Void
    let back: () -> Void
    let next: () -> Void
    /// An arriving wish while it is written in; the whole wish is in `prompt` from the start.
    @State private var arrival: Wish.Arrival?
    /// A browser's copy is waiting that Lamp can't read without macOS asking: the box offers to paste it.
    @State private var pasteOffered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var dictation = Dictation()
    @StateObject private var deck = IdeaDeck()
    @State private var chosen: String?
    @State private var flip = 0
    @FocusState private var focused: Bool
    /// What the idea came from, for `Analytics`: the tile last picked (even if then changed), and dictation.
    @State private var picked = false
    @State private var dictated = false
    /// The dictated phrase the box last gave an Undo step to (`Dictation.phrase`).
    @State private var undoPhrase = 0
    @Environment(\.undoManager) private var undoManager
    @State private var shiftReturn: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Centered in the window, like the first step; the buttons sit along the bottom, and the space kept
            // below stops the content running into them when the window is small.
            Spacer(minLength: 40)
            // The site's own sentence over the wish it wrote, so this reads as the same moment.
            // Mac, iPhone or both is worked out from what they ask for (Store.chooseKind), so nobody chooses.
            Heading(title: wish == nil ? "What would make your day easier, or more fun?" : "Here's your wish. Change anything you like.")

            HStack(alignment: .top, spacing: 10) {
                TextField("", text: box,
                          prompt: Text("Describe what you'd like…").foregroundStyle(.tertiary), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .lineSpacing(3)
                    .lineLimit(3...5)
                    .focused($focused)
                    .allowsHitTesting(arrival == nil)
                    .onChange(of: prompt) { if prompt != deck.ideas.first(where: { $0.id == chosen })?.blurb { chosen = nil } }
                    // Return continues, as in the chat; Shift-Return (`newLineOnShiftReturn`) and Option-Return
                    // start a new line.
                    .onSubmit { if !prompt.trimmed.isEmpty { done() } }
                Button(action: toggleDictation) {
                    Image(systemName: dictation.isListening ? "waveform" : "mic")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(dictation.isListening ? Palette.accent : .secondary)
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
                .strokeBorder(focused ? Palette.accent.opacity(0.55) : .black.opacity(0.08), lineWidth: focused ? 1.5 : 1))
            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
            .overlay(alignment: .bottomTrailing) {
                if pasteOffered && prompt.isEmpty {
                    Button {
                        if let text = Wish.pasted() { paste(text) }
                        pasteOffered = false
                    } label: {
                        Text("Paste my wish")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 30)
                            .background(Palette.accentDeep, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .padding(12)
                    .transition(.opacity)
                }
            }
            .padding(.top, 18)

            HStack {
                Text("Need inspiration?").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    deck.more()
                    Analytics.capture(.welcomeMoreIdeas)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: IdeaDeck.moreSymbol)
                        Text("Show me others")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.accentDeep)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 720)
            .padding(.top, 26)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(Array(deck.ideas.enumerated()), id: \.element.id) { index, idea in
                    IdeaTile(idea: idea, selected: chosen == idea.id) { choose(idea) }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92)).animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.04)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))))
                }
            }
            .frame(width: 720)
            .padding(.top, 10)
            Spacer(minLength: 110)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Footer(back: back) {
                BigButton(title: "Continue", action: done)
                    .disabled(prompt.trimmed.isEmpty)
            } aside: {
                if prompt.trimmed.isEmpty {
                    Button("Skip") {
                        Analytics.capture(.welcomeIdeaSkipped)
                        next()
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            newLineOnShiftReturn()
            deck.prefetch()
            pasteOffered = Wish.offersPaste()
            // After the step has slid in: focus can't land while the old step still holds it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { if !unwritten { focused = true } }
        }
        .onDisappear {
            dictation.cancel()
            shiftReturn.map(NSEvent.removeMonitor)
            shiftReturn = nil
        }
        // Back from the browser with something copied there.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            pasteOffered = Wish.offersPaste()
        }
        .task(id: unwritten) { await write() }
    }

    /// The text field reports Shift-Return as a plain Return, which would continue: the key is turned into a new
    /// line before the field sees it, at the insertion point, unless an input method is composing.
    private func newLineOnShiftReturn() {
        guard shiftReturn == nil else { return }
        shiftReturn = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.contains(.shift),
                  let editor = event.window?.firstResponder as? NSTextView, editor.isFieldEditor, !editor.hasMarkedText()
            else { return event }
            editor.insertNewlineIgnoringFieldEditor(nil)
            return nil
        }
    }

    private func done() {
        let source = chosen != nil ? "picked" : picked ? "edited" : wish != nil ? "site" : "typed"
        Analytics.capture(.welcomeIdeaDone, ["source": source, "dictated": dictated])
        next()
    }

    /// The box shows the wish as far as it has been written; typing is theirs from the first key.
    private var box: Binding<String> {
        Binding { arrival?.text(over: prompt) ?? prompt } set: { typed in
            if let arrival {
                guard typed != arrival.text(over: prompt) else { return }
                self.arrival = nil
            }
            prompt = typed
        }
    }

    /// Writes an arriving wish into the box a word at a time, once.
    private func write() async {
        guard unwritten, let wish else { return }
        defer { unwritten = false }
        if !reduceMotion {
            let steps = Wish.steps(wish)
            let pace = Wish.pace(words: steps.count)
            arrival = Wish.Arrival(wish)
            try? await Task.sleep(for: .seconds(0.45))   // the step slides in first
            // An idea picked or words dictated meanwhile take the box: the writing stops there.
            for step in steps where !Task.isCancelled && arrival != nil && prompt == wish {
                arrival?.advance(to: step)
                try? await Task.sleep(for: pace)
            }
            arrival = nil
        }
        focused = true
        // Focus selects everything in the box, and the next key would then replace the wish: put the caret
        // at its end instead, ready to add to it.
        try? await Task.sleep(for: .seconds(0.1))
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        }
    }

    private func choose(_ idea: Idea) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { chosen = idea.id }
        prompt = idea.blurb
        picked = true
        Analytics.capture(.welcomeIdeaPicked, ["idea": Analytics.idea(idea)])
        focused = true
    }

    private func toggleDictation() {
        if dictation.isListening { return dictation.stop() }
        let typed = prompt.trimmed
        let separator = typed.isEmpty ? "" : " "
        dictated = true
        Analytics.capture(.welcomeDictation)
        Task {
            await dictation.start { heard, before in
                if dictation.phrase != undoPhrase {
                    undoPhrase = dictation.phrase
                    registerUndo(restoring: before.isEmpty ? typed : typed + separator + before)
                }
                prompt = typed + separator + heard
            }
        }
    }

    /// Each dictated phrase is one Undo step, as in the chat's message box (`Composer`): it puts back the box
    /// as it was before the phrase, and stops listening so the next words don't write over it.
    private func registerUndo(restoring earlier: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: dictation) { dictation in
            dictation.cancel()
            registerUndo(restoring: prompt)
            prompt = earlier
        }
        undoManager.setActionName("Dictation")
    }
}

private struct IdeaTile: View {
    let idea: Idea
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    /// How far the hover outline has swept: 0 none, 1 all the way round, 2 gone again (see `SweepOutline`).
    @State private var sweep = 0.0

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                // The symbol alone, without the icon's tile, to leave the wish more room. Gray until hovered
                // or chosen, when it takes the outline's blue.
                Image(systemName: idea.symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(hovering || selected ? Color.blue : Color(white: 0.45))
                    .frame(width: 24, height: 20)
                    // Its top level with the top of the wish's first line.
                    .padding(.top, 3)
                    .animation(.easeOut(duration: 0.2), value: hovering || selected)
                // Just the wish, in the person's words: the name and kind of app are Lamp's business.
                // Room for the same number of lines in every tile, so the grid holds still as ideas change.
                Text(idea.blurb).font(.system(size: 13)).foregroundStyle(Palette.ink)
                    .lineLimit(4, reservesSpace: true)
                    .padding(.top, 1)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(selected ? Color.white : (hovering ? Color.white.opacity(0.9) : Palette.card),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Palette.accent : .black.opacity(0.06), lineWidth: selected ? 1.5 : 1))
            .overlay(SweepOutline(progress: sweep, cornerRadius: 14, color: .blue))
            .shadow(color: .black.opacity(hovering || selected ? 0.08 : 0.03), radius: hovering ? 12 : 6, y: hovering ? 6 : 3)
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { over in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hovering = over }
            // The color comes in from the top left and leaves towards the bottom right. Back over a tile it
            // has left, or is still leaving, it starts in again from the top left.
            if over, sweep >= 1 { sweep = 0 }
            withAnimation(.easeInOut(duration: 0.35)) { sweep = over ? 1 : 2 }
        }
    }
}

/// A tile's outline in `color`, drawn as far as `progress` says along the diagonal from the top left to the
/// bottom right: from 0 (none) it fills in to 1 (all of it), and from 1 to 2 it empties the same way, so the
/// color passes through the tile rather than going back where it came from.
private struct SweepOutline: View, Animatable {
    var progress: Double
    let cornerRadius: CGFloat
    let color: Color

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// How far along the diagonal each edge of the color fades, so it reads as a sweep and not a wipe.
    private static let soft = 0.35

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
            .opacity(progress > 0 && progress < 2 ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// The outline's color at points along the diagonal: past the leading edge it hasn't arrived, behind
    /// the trailing edge it has already gone.
    private var stops: [Gradient.Stop] {
        let soft = Self.soft
        let lead = progress * (1 + soft)
        let trail = (progress - 1) * (1 + soft) - soft
        return (0...16).map { step in
            let at = Double(step) / 16
            let arrived = min(max((lead - at) / soft, 0), 1)
            let remaining = min(max((at - trail) / soft, 0), 1)
            return .init(color: color.opacity(arrived * remaining), location: at)
        }
    }
}

/// 3. Apple's tools, and what builds the apps.
private struct SetupStep: View {
    @EnvironmentObject private var store: Store
    let back: () -> Void
    /// Leaves the welcome and starts the first app.
    let start: () -> Void
    @AppStorage("engine") private var engine = Engine.pi.rawValue
    @AppStorage("piProvider") private var piProvider = "openrouter"
    @State private var choice: Builder.Choice?
    @State private var signedIn: [Engine: Bool] = [:]
    @State private var signingIn: Engine?
    /// Whether the Lamp Agent option on screen (that provider, that model) is the one set up to build.
    @State private var lampReady = false
    @ObservedObject private var downloads = EngineDownloads.shared

    var body: some View {
        // Centered like the other steps. The Lamp Agent options can make it taller than a small window,
        // so it scrolls rather than running into the buttons.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)
                    Heading(title: "Get Lamp ready", detail: "We just need to configure a couple of things.")
                    VStack(spacing: 12) {
                        ToolsCard()
                        BuilderCard(choice: $choice, signedIn: $signedIn, signingIn: $signingIn, lampReady: $lampReady)
                    }
                    .frame(width: 720)
                    .padding(.top, 26)
                    Spacer(minLength: 110)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollIndicators(.never)
        }
        .overlay(alignment: .bottom) {
            Footer(back: back) {
                BigButton(title: "Start building", action: start).disabled(!ready)
            } aside: {
                EmptyView()
            }
        }
        .onAppear {
            if store.setup.hasBuildTools { Analytics.capture(.welcomeToolsReady, ["already_installed": true]) }
            if !store.setup.hasBuildTools && !store.setup.installRequested {
                store.requestBuildTools()
                Analytics.capture(.welcomeToolsInstall, ["by": "automatic"])
            }
            choice = Builder.Choice.current(engine: engine, piProvider: piProvider, ready: store.setup.hasBuilder)
        }
        .task { await refreshSignIns() }
        .onChange(of: store.setup.hasBuildTools) { _, has in
            if has { Analytics.capture(.welcomeToolsReady, ["already_installed": false]) }
        }
        .onChange(of: downloads.revision) { Task { await refreshSignIns() } }   // Lamp's copy arrived
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from signing in.
            Task {
                await store.recheckSetup()
                await refreshSignIns()
            }
        }
    }

    /// Ready once something can build. Claude Code and ChatGPT also need to be signed in.
    private var ready: Bool {
        guard store.setup.hasBuilder, let choice, choice.matches(engine: engine, piProvider: piProvider) else { return false }
        switch choice {
        case .claude: return signedIn[.claude] == true
        case .chatGPT: return signedIn[.codex] == true
        default: return lampReady
        }
    }

    /// A check that can't tell counts as signed out: the Sign In button is then the way to find out.
    private func refreshSignIns() async {
        for engine in [Engine.claude, .codex] where EngineInstall.path(for: engine) != nil && signingIn != engine {
            signedIn[engine] = await EngineSignIn.isSignedIn(engine) ?? false
        }
    }
}

extension Builder {
    /// What the welcome offers to build apps with.
    enum Choice: Hashable {
        case claude, chatGPT, openRouter, another, onThisMac

        var isForge: Bool { self != .claude && self != .chatGPT }

        static func current(engine: String, piProvider: String, ready: Bool) -> Choice? {
            guard ready else { return nil }
            switch Engine(rawValue: engine) {
            case .claude: return .claude
            case .codex: return .chatGPT
            default:
                switch piProvider {
                case "openrouter": return .openRouter
                case let id where Provider.apiProvider(id) != nil || LocalModels.externalIDs.contains(id): return .another
                default: return .onThisMac
                }
            }
        }

        func matches(engine: String, piProvider: String) -> Bool {
            let forge = engine == Engine.pi.rawValue
            switch self {
            case .claude: return engine == Engine.claude.rawValue
            case .chatGPT: return engine == Engine.codex.rawValue
            case .openRouter: return forge && piProvider == "openrouter"
            case .another:
                return forge && piProvider != "openrouter"
                    && (Provider.apiProvider(piProvider) != nil || LocalModels.externalIDs.contains(piProvider))
            case .onThisMac:
                return forge && Provider.apiProvider(piProvider) == nil && !LocalModels.externalIDs.contains(piProvider)
            }
        }
    }

    /// A good model to start with from a provider's list: the strongest current one, never a small or
    /// preview model, so a first app has the best chance.
    static func suggestedModel(_ models: [String], provider: String) -> String? {
        let favorites: [String: [String]] = [
            "anthropic": ["claude-opus-5-5", "claude-sonnet-5-5", "claude-opus-5"],
            "google": ["gemini-3.1-pro-preview", "gemini-2.5-pro"],
        ]
        if let favorite = favorites[provider]?.first(where: models.contains) { return favorite }
        // OpenAI and others name their main line "gpt-5.2" and so on: take the newest plain one.
        let plain = models.filter { $0.range(of: #"^gpt-\d+(\.\d+)?$"#, options: .regularExpression) != nil }
        if let newest = plain.max(by: { $0.compare($1, options: .numeric) == .orderedAscending }) { return newest }
        let small = ["mini", "nano", "lite", "haiku", "preview", "latest", "audio", "image", "realtime", "search",
                     "embed", "tts", "transcribe", "instruct"]
        return models.last { model in !small.contains { model.lowercased().contains($0) } } ?? models.last
    }
}

private struct ToolsCard: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Install Apple's app-building tools").font(.system(size: 15, weight: .semibold))
                    detail
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                switch store.setup.installStage {
                case .installed:
                    Done()
                case .inApplesWindow, .installing:
                    ProgressView().controlSize(.small)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 20)).foregroundStyle(.white, .orange)
                case .notAsked:
                    Button("Install") {
                        store.requestBuildTools()
                        Analytics.capture(.welcomeToolsInstall, ["by": "button"])
                    }
                }
            }
        }
    }

    /// One line that follows the install along, with the one thing to click when there is one.
    @ViewBuilder private var detail: some View {
        switch store.setup.installStage {
        case .notAsked:
            Text("Free from Apple, and no developer account needed.")
        case .inApplesWindow:
            Text("In Apple's window, click Install, then Agree. It takes 5–10 minutes.")
        case .installing:
            HStack(spacing: 8) {
                Text("Installing…")
                InlineButton(title: "Show Installer", action: SetupCheck.showInstaller)
            }
        case .failed:
            HStack(spacing: 8) {
                Text("The install didn't finish.")
                InlineButton(title: "Try Again") {
                    store.requestBuildTools()
                    Analytics.capture(.welcomeToolsInstall, ["by": "retry"])
                }
            }
        case .installed:
            Text("Installed.")
        }
    }
}

/// A small button that sits in a line of text, after what it acts on.
private struct InlineButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered).controlSize(.small)
    }
}

private struct BuilderCard: View {
    @EnvironmentObject private var store: Store
    @Binding var choice: Builder.Choice?
    @Binding var signedIn: [Engine: Bool]
    @Binding var signingIn: Engine?
    @Binding var lampReady: Bool
    @AppStorage("engine") private var engine = Engine.pi.rawValue
    @State private var problem: String?
    @ObservedObject private var downloads = EngineDownloads.shared

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose your AI agent").font(.system(size: 15, weight: .semibold))
                    Text("You can change this any time.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Option(selected: choice == .claude, title: "Claude Code", detail: "Uses your Claude subscription") {
                        ProviderLogo(id: "anthropic", size: 30)
                    } action: { pick(.claude) }
                    Option(selected: choice == .chatGPT, title: "ChatGPT", detail: "Uses your ChatGPT subscription") {
                        ProviderLogo(id: "openai", size: 30)
                    } action: { pick(.chatGPT) }
                    Option(selected: choice?.isForge == true, title: "Lamp Agent", detail: "You choose the AI") {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                    } action: { pick(choice?.isForge == true ? choice! : .openRouter) }
                }
                if let choice {
                    Group {
                        switch choice {
                        case .claude: account(.claude, app: "Claude")
                        case .chatGPT: account(.codex, app: "ChatGPT")
                        default: LampAgentOptions(choice: Binding(get: { choice }, set: { pick($0) }), ready: $lampReady)
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: -6)))
                    .id(choice.isForge ? "lamp" : "\(choice)")
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: choice)
        }
    }

    /// Choosing a card is choosing the agent: a sign-in picks its tool straight away, Lamp downloads its
    /// own copy of the tool if the Mac has none, and only the sign-in is asked for underneath.
    private func pick(_ new: Builder.Choice) {
        problem = nil
        if choice != new {
            var properties: [String: Any] = ["agent": Analytics.agent(new)]
            if new == .claude { properties["installed"] = EngineInstall.path(for: .claude) != nil }
            if new == .chatGPT { properties["installed"] = EngineInstall.path(for: .codex) != nil }
            Analytics.capture(.welcomeAgent, properties)
        }
        choice = new
        let which: Engine? = new == .claude ? .claude : new == .chatGPT ? .codex : nil
        guard let which else { return }
        // Saved whether or not a copy is here yet: once it is and is signed in, the choice stands.
        Builder.engine = which
        engine = which.rawValue
        guard EngineInstall.path(for: which) != nil else { downloads.start(which); return }
        Task {
            if signedIn[which] == nil { signedIn[which] = await EngineSignIn.isSignedIn(which) ?? false }
            await store.recheckSetup()
        }
    }

    /// Claude Code or ChatGPT: Lamp's copy downloading when the Mac has none, then the sign-in if it's not done yet.
    @ViewBuilder
    private func account(_ which: Engine, app: String) -> some View {
        let installed = EngineInstall.path(for: which) != nil
        let name = which == .claude ? "Claude Code" : app
        HStack(spacing: 10) {
            if !installed, let failure = downloads.failure[which] {
                Text(failure).font(.system(size: 13)).foregroundStyle(Color.orange)
                Spacer()
                Button("Try Again") { downloads.start(which) }
            } else if !installed {
                ProgressView(value: downloads.progress[which] ?? 0).frame(width: 120)
                Text("Getting \(name) ready…").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            } else if signedIn[which] == true {
                Done()
                Text("\(name) will make your apps.").font(.system(size: 13, weight: .medium))
                Spacer()
            } else if signingIn == which {
                ProgressView().controlSize(.small)
                Text("Finish signing in to \(app) in your browser…").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                // A sign-in page opened in the wrong browser profile or for the wrong account can't be finished.
                Button("Cancel") { EngineSignIn.cancelSignIn(which) }
            } else if signedIn[which] == nil {
                ProgressView().controlSize(.small)
                Text("Checking your \(app) sign-in…").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            } else {
                // Claude's free plan doesn't include Claude Code: said before the browser, not after a failed build.
                Text(problem ?? "Sign in to \(app) so \(name) can build.\(which == .claude ? " It needs a paid Claude plan." : "")")
                    .font(.system(size: 13)).foregroundStyle(problem == nil ? Color.secondary : Color.orange)
                Spacer()
                Button("Sign In…") { signIn(which) }
            }
        }
        .padding(.top, 2)
    }

    private func signIn(_ which: Engine) {
        problem = nil
        Task {
            signingIn = which
            Analytics.capture(.welcomeSignIn, ["agent": Analytics.agent(which)])
            let result = await EngineSignIn.signIn(which)
            Analytics.capture(.welcomeSignedIn, ["agent": Analytics.agent(which), "success": result == true])
            signingIn = nil
            NSApp.activate()
            // Cancelled: back to Sign In…, with nothing to apologise for.
            signedIn[which] = await EngineSignIn.isSignedIn(which) ?? (result == true)
            if result == false { problem = "Signing in didn't finish. Try again." }
            await store.recheckSetup()
        }
    }
}

/// Lamp's own agent: OpenRouter, another provider, or a model on this Mac, each set up right here.
private struct LampAgentOptions: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var local = LocalModels.shared
    @Binding var choice: Builder.Choice
    @Binding var ready: Bool
    @AppStorage("engine") private var engine = Engine.pi.rawValue
    @AppStorage("piProvider") private var piProvider = "openrouter"
    @State private var key = ""
    @State private var checkingKey = false
    @State private var problem: String?
    @State private var provider = "anthropic"
    @State private var models: [String] = []
    @State private var model = ""
    @State private var localChoice = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Radio(title: "OpenRouter", selected: choice == .openRouter) { pick(.openRouter) } content: {
                openRouter
            }
            Radio(title: "Another provider", selected: choice == .another) { pick(.another) } content: {
                anotherProvider
            }
            Radio(title: "A model on this Mac", selected: choice == .onThisMac) { pick(.onThisMac) } content: {
                onThisMac
            }
        }
        .padding(.top, 2)
        .onAppear {
            if piProvider != "openrouter", Provider.apiProvider(piProvider) != nil || LocalModels.externalIDs.contains(piProvider) {
                provider = piProvider
            }
            localChoice = defaultLocalChoice()
            apply()
        }
        // Ready only when what's on screen is exactly what will build: not a provider chosen before, nor a
        // model that isn't downloaded yet.
        .onChange(of: showsReady, initial: true) { ready = showsReady }
        .onChange(of: local.installed) {
            // A download finished: switch to the model it installed, and use it.
            if let spec = spec(localChoice), let id = local.installedID(for: spec) {
                localChoice = "installed:" + id
                apply()
            }
        }
    }

    private func pick(_ new: Builder.Choice) {
        guard choice != new else { return }
        problem = nil
        key = ""
        choice = new
        apply()
    }

    /// Uses the chosen option straight away when it's ready (a saved key, a downloaded model).
    private func apply() {
        switch choice {
        case .openRouter:
            if KeyStore.key(for: "openrouter") != nil { use(provider: "openrouter", model: nil) }
        case .another:
            if providerReady, models.contains(model) { use(provider: provider, model: model) }
        case .onThisMac:
            if localChoice.hasPrefix("installed:") { use(provider: Builder.localProvider, model: String(localChoice.dropFirst(10))) }
        default:
            break
        }
    }

    private func use(provider id: String, model chosen: String?) {
        Builder.engine = .pi
        Builder.piProvider = id
        if let chosen { Builder.piModel = chosen }
        engine = Engine.pi.rawValue
        piProvider = id
        Task { await store.recheckSetup() }
    }

    private var showsReady: Bool {
        guard isUsing(choice) else { return false }
        switch choice {
        case .openRouter:
            return piProvider == "openrouter"
        case .another:
            return piProvider == provider && providerReady && models.contains(model) && Builder.piModel == model
        case .onThisMac:
            return localChoice.hasPrefix("installed:") && piProvider == Builder.localProvider
                && Builder.piModel == String(localChoice.dropFirst(10))
        default:
            return false
        }
    }

    private func isUsing(_ option: Builder.Choice) -> Bool {
        store.setup.hasBuilder && option.matches(engine: engine, piProvider: piProvider)
    }

    // MARK: OpenRouter

    @ViewBuilder private var openRouter: some View {
        if isUsing(.openRouter) {
            ready("Your OpenRouter key is saved.")
        } else {
            note("Hundreds of AI models, paying OpenRouter only for what you use.")
            keyField(name: "OpenRouter", url: "https://openrouter.ai/keys", save: saveOpenRouterKey)
        }
    }

    /// Checks the key with OpenRouter before saving it, so a typo shows up now rather than at the first build.
    private func saveOpenRouterKey() {
        let candidate = key.trimmed
        guard !candidate.isEmpty, !checkingKey else { return }
        checkingKey = true
        Task {
            defer { checkingKey = false }
            if let found = await SetupView.checkOpenRouterKey(candidate) {
                Analytics.capture(.welcomeKey, ["valid": false])
                problem = found
                return
            }
            Analytics.capture(.welcomeKey, ["valid": true])
            KeyStore.setOpenRouterKey(candidate)
            key = ""
            use(provider: "openrouter", model: nil)
        }
    }

    // MARK: Another provider

    /// Cloud providers and the model apps on this Mac Lamp can talk to, in one alphabetical list.
    private var others: [(id: String, name: String)] {
        (Provider.apiProviders.filter { $0.id != "openrouter" }.map { ($0.id, $0.name) }
            + LocalModels.externalIDs.map { ($0, LocalModels.externalName($0)) })
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var isServer: Bool { LocalModels.externalIDs.contains(provider) }

    /// Ready to build: a cloud provider with its key, or a model app that's running with a model in it.
    private var providerReady: Bool { isServer ? !models.isEmpty : KeyStore.key(for: provider) != nil }

    @ViewBuilder private var anotherProvider: some View {
        let name = others.first { $0.id == provider }?.name ?? provider
        HStack(spacing: 10) {
            Picker("", selection: $provider) {
                ForEach(others, id: \.id) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .frame(width: 200)
            if providerReady && !models.isEmpty {
                Picker("", selection: $model) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
        }
        .onChange(of: provider) {
            // The last provider's models don't belong to this one: nothing to pick until its own list is in.
            models = []
            model = ""
            key = ""
            problem = nil
            Task { await loadModels() }
        }
        .onChange(of: model) {
            guard models.contains(model) else { return }
            UserDefaults.standard.set(model, forKey: "piModel.\(provider)")
            apply()
        }
        .task { await loadModels() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from opening Ollama or LM Studio.
            if isServer { Task { await loadModels() } }
        }
        if isServer {
            if models.isEmpty {
                HStack(spacing: 10) {
                    note("Open \(name) with a model downloaded in it, and Lamp finds it here.")
                    Spacer()
                    Link("Get \(name)", destination: URL(string: provider == "ext-ollama" ? "https://ollama.com/download" : "https://lmstudio.ai")!)
                        .font(.system(size: 13, weight: .medium))
                }
            } else if isUsing(.another) && piProvider == provider {
                ready("\(name) will make your apps, right here on this Mac.")
            }
        } else if let current = Provider.apiProvider(provider) {
            if KeyStore.key(for: provider) != nil {
                if isUsing(.another) && piProvider == provider {
                    ready("Your \(current.name) key is saved.")
                }
            } else {
                keyField(name: current.name, url: current.keyURL) {
                    let candidate = key.trimmed
                    guard !candidate.isEmpty else { return }
                    KeyStore.setKey(candidate, for: provider)
                    key = ""
                    Task {
                        await loadModels()
                        apply()
                    }
                }
            }
        }
    }

    private func loadModels() async {
        let id = provider
        let list: [String]
        if LocalModels.externalIDs.contains(id) {
            await local.detectExternal()
            list = local.external[id] ?? []
        } else {
            list = await Agent.listModels(provider: id)
        }
        guard id == provider else { return }
        models = list
        let saved = UserDefaults.standard.string(forKey: "piModel.\(id)") ?? ""
        model = list.contains(saved) ? saved : (Builder.suggestedModel(list, provider: id) ?? "")
        apply()
    }

    // MARK: A model on this Mac

    private var recommended: LocalModelSpec? {
        LocalModels.catalog.filter { $0.minRAMGB <= LocalModels.ramGB }.max { $0.minRAMGB < $1.minRAMGB }
            ?? LocalModels.catalog.min { $0.minRAMGB < $1.minRAMGB }
    }

    /// "installed:<id>" for a model on this Mac, "spec:<id>" for one to download.
    private func defaultLocalChoice() -> String {
        if Builder.piProvider == Builder.localProvider, local.installed.contains(where: { $0.id == Builder.piModel }) {
            return "installed:" + Builder.piModel
        }
        if let recommended, let id = local.installedID(for: recommended) { return "installed:" + id }
        if let first = local.installed.first { return "installed:" + first.id }
        return recommended.map { "spec:" + $0.id } ?? ""
    }

    private func spec(_ tag: String) -> LocalModelSpec? {
        guard tag.hasPrefix("spec:") else { return nil }
        return LocalModels.catalog.first { $0.id == tag.dropFirst(5) }
    }

    @ViewBuilder private var onThisMac: some View {
        note("Free and private: Lamp runs the model right here. Smaller models make simpler apps.")
        Picker("", selection: $localChoice) {
            ForEach(local.installed) { Text("\($0.name) (on this Mac)").tag("installed:" + $0.id) }
            ForEach(LocalModels.catalog.filter { !local.isInstalled($0) }) { spec in
                Text(spec.name + (spec == recommended ? " (recommended)" : "")).tag("spec:" + spec.id)
            }
        }
        .labelsHidden()
        .frame(width: 320)
        .onChange(of: localChoice) { apply() }
        if let spec = spec(localChoice) {
            HStack(spacing: 10) {
                Text(String(format: "%@ %.1f GB download, needs %d GB of memory.", spec.blurb, spec.sizeGB, spec.minRAMGB))
                    .font(.system(size: 12)).foregroundStyle(spec.minRAMGB > LocalModels.ramGB ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let progress = local.progress[spec.id] {
                    ProgressView(value: progress).frame(width: 100)
                    Button("Cancel") { local.cancel(spec.id) }
                } else {
                    Button("Download") {
                        local.download(spec)
                        Analytics.capture(.welcomeModelDownload, ["model": spec.id])
                    }
                }
            }
            if let error = local.errors[spec.id] {
                Text(error).font(.system(size: 12)).foregroundStyle(.orange)
            }
        } else if isUsing(.onThisMac) {
            ready("\(local.installed.first { "installed:" + $0.id == localChoice }?.name ?? "This model") will make your apps.")
        }
    }

    // MARK: Pieces

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func ready(_ text: String) -> some View {
        HStack(spacing: 8) {
            Done()
            Text(text).font(.system(size: 13, weight: .medium))
        }
    }

    @ViewBuilder
    private func keyField(name: String, url: String, save: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            SecureField("Paste your \(name) key", text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
                .onChange(of: key) { problem = nil }
            if checkingKey {
                ProgressView().controlSize(.small)
            } else {
                Button("Save", action: save).disabled(key.trimmed.isEmpty)
            }
            Link("Get a key", destination: URL(string: url)!)
                .font(.system(size: 13, weight: .medium))
        }
        if let problem {
            Label(problem, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
        }
    }
}

/// A radio button whose own settings open up right beneath it when it's chosen.
private struct Radio<Content: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().strokeBorder(selected ? Palette.accent : .black.opacity(0.25), lineWidth: selected ? 5 : 1)
                            .background(Circle().fill(.white))
                    }
                    .frame(width: 16, height: 16)
                    Text(title).font(.system(size: 13.5, weight: selected ? .semibold : .regular)).foregroundStyle(Palette.ink)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            if selected {
                VStack(alignment: .leading, spacing: 8) { content() }
                    .padding(.leading, 24)
                    .transition(.opacity)
            }
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
                .strokeBorder(selected ? Palette.accent : .black.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { over in withAnimation(.easeOut(duration: 0.15)) { hovering = over } }
    }
}

// MARK: - Pieces

private struct Heading: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 38, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Palette.ink)
            if let detail {
                Text(detail)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
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

/// Back on the left, the way forward on the right, anything else in the middle.
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
            primary()
        }
        // Anything secondary, like "Skip", sits in the middle.
        .overlay { aside() }
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
                    Capsule().fill(LinearGradient(colors: [Palette.accent, Palette.accentDeep], startPoint: .top, endPoint: .bottom))
                )
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Palette.accentDeep.opacity(enabled ? (hovering ? 0.4 : 0.28) : 0), radius: hovering ? 16 : 10, y: 6)
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
                    .fill(step == current ? Palette.accent : Color.black.opacity(0.13))
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
    /// Fades in a beat after `delay`, rising `rise` points into place. Only the fade and the rise animate:
    /// layout changes at the same moment (the window settling its size) happen at once, not as a drift.
    func reveal(_ shown: Bool, delay: Double, rise: CGFloat = 14) -> some View {
        animation(.spring(response: 0.7, dampingFraction: 0.85).delay(delay)) {
            $0.opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : rise)
                .blur(radius: shown ? 0 : 6)
        }
    }
}

// MARK: - Window

/// Settings waits until the welcome is done: everything it would offer is set up in the welcome itself.
/// A menu item without an action is grayed out, and so is its ⌘, shortcut.
enum SettingsMenu {
    private static let open = Selector(("showSettingsWindow:"))

    static func enable(_ on: Bool) {
        guard let menu = NSApp.mainMenu?.items.first?.submenu else { return }
        for item in menu.items where item.title.hasPrefix("Settings") {
            if on, item.action == nil { item.action = open }
            if !on, item.action != nil { item.action = nil }
        }
    }
}

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
/// the window gets its chrome back and grows into Lamp's, around the same center.
private enum Chrome {
    private static var saved: (mask: NSWindow.StyleMask, transparent: Bool, title: NSWindow.TitleVisibility, movable: Bool,
                               name: String, minSize: NSSize, maxSize: NSSize)?

    static func hide(_ window: NSWindow) {
        guard saved == nil else { return }
        saved = (window.styleMask, window.titlebarAppearsTransparent, window.titleVisibility, window.isMovableByWindowBackground,
                 window.title, window.contentMinSize, window.contentMaxSize)
        window.title = ""
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.resizable)
        window.contentMinSize = Onboarding.size
        window.contentMaxSize = Onboarding.size
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
            window.styleMask.remove(.resizable)
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
        window.contentMaxSize = saved.maxSize
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
