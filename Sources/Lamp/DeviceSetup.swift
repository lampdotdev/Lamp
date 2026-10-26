import Combine
import AppKit
import SwiftUI
import LampSidebarKit

/// Setting up a device that has an integration, step by step, drawn from the integration's data: one window for every
/// such device (`DeviceSetupWindow`), and the same card in the chat when a wish needs the step (`DeviceStepLine`).
/// Each device has one model (`DeviceSetupModel.for`), so the window and the chat show the same state. A step is done
/// when its check passes, never because anyone said so; one that needs hands on the device is checked again and
/// again until it passes.
@MainActor
final class DeviceSetupModel: ObservableObject {
    private static var models: [String: DeviceSetupModel] = [:]

    static func `for`(_ device: Device) -> DeviceSetupModel {
        if let model = models[device.id] {
            if model.device != device { model.device = device }
            return model
        }
        let model = DeviceSetupModel(device: device)
        models[device.id] = model
        return model
    }

    static func existing(_ deviceID: String) -> DeviceSetupModel? { models[deviceID] }

    /// Lets go of a device's setup as it stands in this Lamp, for Forget: its watch stops, a command waiting for the
    /// person's yes is turned down, and what waited for it to be ready isn't run. Found again, it starts afresh.
    static func discard(_ deviceID: String) {
        // Its window shows this model: closed, so a setup started again opens on a fresh one.
        DeviceSetupWindow.close(deviceID)
        guard let model = models.removeValue(forKey: deviceID) else { return }
        model.stopWatching()
        if model.approval != nil { model.decide(false) }
        model.then = nil
    }

    @Published var device: Device
    @Published private(set) var passed: [String] = []
    @Published var typed = ""
    @Published private(set) var state: DeviceStepCard.State = .idle
    /// A command or tool waiting for the person's yes.
    @Published private(set) var approval: DeviceCommandApproval?
    /// The device showed another certificate than the one Lamp kept (`DeviceTLS`): nothing goes to it until the person
    /// reconnects it. Shown in place of a step's card, wherever the device's setup is.
    @Published private(set) var certificateChanged = false
    /// The test run's stages while it runs, and after (`IntegrationProbe`).
    @Published private(set) var trial: [IntegrationProbe.Stage] = []
    private var answer: CheckedContinuation<Bool, Never>?
    private var watching: Task<Void, Never>?
    /// What asked for the setup, run once the device is ready.
    var then: (() -> Void)?

    private init(device: Device) {
        self.device = device
        passed = Integrations.kept(device.id)?.passed ?? []
        // A card may show Lamp's public key, which is made the first time it's needed: made now, the card is drawn again.
        if let runner, runner.needsSSHKey, DeviceSSH.publicKey == nil {
            Task { [weak self] in
                await runner.prepare()
                self?.objectWillChange.send()
            }
        }
    }

    var integration: Integration? { device.integration.flatMap(Integrations.integration) }

    /// Whether a test run can start: the device is set up, its integration makes apps, and none is running.
    var canTry: Bool { ready && integration?.app?.declared != nil && !trial.contains { $0.state == .running } }

    /// Puts a test app on the device and back off, at the person's press.
    func tryIt() {
        guard canTry, let integration else { return }
        let device = device
        Task { await IntegrationProbe.run(integration, on: device) { [weak self] in self?.trial = $0 } }
    }

    /// The bridge's mark from a test run that passed, in the person's words.
    var worked: String? {
        guard let known = integration?.bridge?.known, let model = known.model else { return nil }
        return "Apps worked on \(model)" + (known.version.map { ", \($0)" } ?? "")
    }
    var steps: [Integration.Step] { integration?.steps ?? [] }
    var next: Integration.Step? { steps.first { !passed.contains($0.id) } }
    var ready: Bool { integration != nil && next == nil }

    private var runner: IntegrationRunner? {
        guard let integration else { return nil }
        return IntegrationRunner(integration: integration, device: device, approve: { [weak self] approval in
            await self?.ask(approval) ?? false
        })
    }

    /// The card's content for the step the device is at.
    var content: DeviceStepCard.Content? {
        guard let step = next, let runner else { return nil }
        let number = (steps.firstIndex(of: step) ?? 0) + 1
        // Only Lamp's own values: a card shows nothing the person typed, and isn't drawn after a read of the Keychain.
        return DeviceStepCard.Content(step: step, number: number, of: steps.count, device: device.name, values: runner.values(secrets: false), state: state)
    }

    /// The step's one button: what it runs, then its check. A step that needs hands on the device starts watching.
    func act() {
        guard let step = next, let runner, !state.isBusy else { return }
        if let field = step.field {
            guard !typed.trimmed.isEmpty else { state = .failed("Type the \(field.label.lowercased()) first."); return }
            DeviceFields.save(typed, as: field.key, device: device.id)
            typed = ""
        }
        Task {
            if let run = step.run, !run.isEmpty {
                state = .working(step.run?.contains { $0.vendorSignIn != nil } == true ? "Waiting for you to sign in…" : "Working…")
                do { _ = try await runner.run(run) } catch {
                    state = .failed(error.localizedDescription)
                    return
                }
            }
            await checkOnce(step, runner: runner, keepWatching: step.wait == true)
        }
    }

    /// Looks at the step's check, and for a step done on the device keeps looking every few seconds while it's shown.
    func watch() {
        guard let step = next, step.wait == true, watching == nil, let runner else { return }
        watching = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.next == step else { break }
                await self.checkOnce(step, runner: runner, keepWatching: false, quietly: true)
                if self.passed.contains(step.id) { break }
                if case .failed = self.state { return }
                try? await Task.sleep(for: .seconds(3))
            }
            guard !Task.isCancelled else { return }
            self?.watching = nil
            self?.watch()
        }
    }

    func stopWatching() {
        watching?.cancel()
        watching = nil
    }

    private func checkOnce(_ step: Integration.Step, runner: IntegrationRunner, keepWatching: Bool, quietly: Bool = false) async {
        // The watch's look every few seconds leaves the card as it is: only a check the person asked for shows as
        // checking, so nothing on the card blinks while they're at the device.
        if !quietly, !state.isBusy || state == .checking { state = .checking }
        let (ok, why, read, failed) = await runner.check(step)
        guard next == step else { return }
        if ok {
            runner.passed(step, read: read)
            passed = Integrations.kept(device.id)?.passed ?? passed + [step.id]
            state = .idle
            Store.shared.refreshDevices()
            if ready { then?(); then = nil } else { watch() }
        } else if failed {
            // Waiting won't mend it: the card says why, and nothing goes on checking.
            if why == DeviceTLS.Refusal.changed.localizedDescription { certificateChanged = true }
            state = .failed(why ?? "\(device.name) can't be checked.")
            stopWatching()
        } else {
            state = .waiting(why ?? "Waiting for \(device.name)…")
            if keepWatching { watch() }
        }
    }

    /// Lamp refused the device's certificate outside a setup step (putting an app on it): the reconnect card shows.
    func noteCertificateChanged() { certificateChanged = true }

    /// The person's Reconnect: the certificate kept for the device is let go and its setup starts again from the first
    /// step, so the sign-in it asks for goes only to the device whose new certificate the first request keeps. Only a
    /// click does this; a changed certificate never makes Lamp trust the new one by itself.
    func reconnect() {
        DeviceTLS.Pins(deviceID: device.id).forget()
        // Its SSH host key too, which a reset device changes as it does its certificate.
        try? FileManager.default.removeItem(at: DeviceFolder.of(device.id).appendingPathComponent("known_hosts"))
        Integrations.startOver(device.id)
        passed = []
        typed = ""
        state = .idle
        certificateChanged = false
        Store.shared.refreshDevices()
        watch()
    }

    private func ask(_ approval: DeviceCommandApproval) async -> Bool {
        DeviceSetupWindow.show(self)
        return await withCheckedContinuation { continuation in
            answer?.resume(returning: false)
            answer = continuation
            self.approval = approval
        }
    }

    func decide(_ allowed: Bool) {
        approval = nil
        answer?.resume(returning: allowed)
        answer = nil
    }
}

// MARK: - The window

@MainActor
final class DeviceSetupWindow: NSObject, NSWindowDelegate {
    private static var windows: [String: NSWindow] = [:]
    private static var delegates: [String: DeviceSetupWindow] = [:]
    private let model: DeviceSetupModel
    private var resizing: AnyCancellable?

    private init(model: DeviceSetupModel) { self.model = model }

    /// The setup window for a device with an integration; runs `then` once it's ready (at once if it is).
    static func show(_ device: Device, then: (() -> Void)? = nil) {
        let model = DeviceSetupModel.for(device)
        if model.ready, let then { then(); return }
        if let then { model.then = then }
        show(model)
    }

    static func show(_ model: DeviceSetupModel) {
        let id = model.device.id
        if windows[id] == nil {
            let (window, resizing) = FittedWindow.make(DeviceSetupView(model: model), following: model.objectWillChange)
            let delegate = DeviceSetupWindow(model: model)
            delegate.resizing = resizing
            window.delegate = delegate
            delegates[id] = delegate
            window.center()
            windows[id] = window
        }
        windows[id]?.title = "Set Up \(model.device.name)"
        windows[id]?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.watch()
    }

    /// Closes a device's setup window, for Forget.
    static func close(_ deviceID: String) { windows[deviceID]?.close() }

    func windowWillClose(_ notification: Notification) {
        model.stopWatching()
        if model.approval != nil { model.decide(false) }
        Self.windows[model.device.id] = nil
        Self.delegates[model.device.id] = nil
    }
}

struct DeviceSetupView: View {
    @ObservedObject var model: DeviceSetupModel

    var body: some View {
        let conversation = Store.shared.projects.first { $0.deviceSetup == model.device.id }
        DeviceSetupPage(device: model.device, steps: model.steps, passed: model.passed, content: model.content, typed: $model.typed,
                        approval: model.approval, act: model.act, decide: model.decide,
                        ask: conversation.map { project in { Store.shared.showChat(project.id) } },
                        reconnect: model.certificateChanged ? { model.reconnect() } : nil,
                        trial: model.trial, tryIt: model.integration?.app?.declared != nil ? { model.tryIt() } : nil,
                        canTry: model.canTry, worked: model.worked)
    }
}

/// The window's content from plain values, as the gallery draws it: the device, its steps with done, next and not yet,
/// and the next step's card (or the approval it waits on).
struct DeviceSetupPage: View {
    let device: Device
    let steps: [Integration.Step]
    let passed: [String]
    let content: DeviceStepCard.Content?
    @Binding var typed: String
    let approval: DeviceCommandApproval?
    let act: () -> Void
    let decide: (Bool) -> Void
    /// Back to the device's setup conversation, where a step that doesn't work is talked through.
    var ask: (() -> Void)? = nil
    /// Set while the device's certificate has changed: the reconnect card takes the step card's place.
    var reconnect: (() -> Void)? = nil
    /// Once it's set up, for a device that takes apps: a test run's stages, its button, and how its bridge is known.
    var trial: [IntegrationProbe.Stage] = []
    var tryIt: (() -> Void)? = nil
    var canTry = true
    var worked: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: device.kind.symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.secondary).frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up \(device.name)").font(.title2.weight(.semibold))
                    Text(device.line).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let ask { Button("Ask About Setup…", action: ask) }
            }
            .padding(.bottom, 16)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { Divider().padding(.leading, 44) }
                    let done = passed.contains(step.id)
                    let current = !done && steps.first(where: { !passed.contains($0.id) })?.id == step.id
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark.circle.fill" : current ? "arrow.forward.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(done ? AnyShapeStyle(Color.green) : current ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                            .frame(width: 20)
                        Text(step.title).fontWeight(current ? .semibold : .regular).opacity(done || current ? 1 : 0.6)
                        Spacer(minLength: 0)
                        Text(done ? "Done" : current ? "Next" : "Not yet").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            if let reconnect {
                DeviceReconnectCard(device: device.name, reconnect: reconnect).padding(.top, 16)
            } else if let approval {
                DeviceCommandCard(approval: approval, allow: { decide(true) }, deny: { decide(false) }).padding(.top, 16)
            } else if let content {
                DeviceStepCard(content: content, typed: $typed, act: act).padding(.top, 16)
            } else if !steps.isEmpty {
                Label("\(device.name) is set up.", systemImage: "checkmark.circle.fill").foregroundStyle(.green).padding(.top, 16)
                if let tryIt { DeviceTrialCard(device: device.name, stages: trial, worked: worked, enabled: canTry, tryIt: tryIt).padding(.top, 12) }
            }
        }
        .padding(20)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - A step's card

/// One setup step, drawn from its data: what to do in numbered lines, Lamp's values shown large, a QR code, the field
/// to type in, the page to read, what the person accepts (Lamp's sentences), how the step is known, the one button
/// and the check's line. The same card in the setup window and in the chat.
struct DeviceStepCard: View {
    enum State: Equatable {
        case idle, checking
        case working(String)
        case waiting(String)
        case failed(String)
        var isBusy: Bool { if case .working = self { return true }; return self == .checking }
    }

    struct Content: Equatable {
        var device: String
        var number: Int
        var of: Int
        var title: String
        var lines: [String] = []
        var shown: [Shown] = []
        var qr: String?
        var field: Field?
        var link: URL?
        var signIn: String?
        var accepts: [String] = []
        var mark: String
        var markSymbol: String
        var markDetail: String
        var button: String?
        var state: State = .idle

        struct Shown: Equatable { var label: String; var value: String }
        struct Field: Equatable { var label: String; var secret: Bool }
    }

    let content: Content
    @Binding var typed: String
    let act: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(content.title).font(.headline)
                Spacer(minLength: 8)
                Text("Step \(content.number) of \(content.of)").font(.caption).foregroundStyle(.secondary)
            }
            if !content.lines.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(content.lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary).frame(width: 18, alignment: .trailing)
                            Text(line).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            ForEach(Array(content.shown.enumerated()), id: \.offset) { _, shown in
                VStack(alignment: .leading, spacing: 2) {
                    Text(shown.label).font(.caption).foregroundStyle(.secondary)
                    Text(shown.value).font(.system(size: 22, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                }
            }
            if let qr = content.qr, let image = DeviceQR.image(qr) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 140, height: 140)
                    .accessibilityLabel("A code to scan")
            }
            if let field = content.field {
                Group {
                    if field.secret { SecureField(field.label, text: $typed) } else { TextField(field.label, text: $typed) }
                }
                .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                .onSubmit(act)
            }
            if let link = content.link {
                Link("Read how on \(link.host ?? "the web")", destination: link)
            }
            if !content.accepts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What you accept").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(content.accepts, id: \.self) { sentence in
                        Label(sentence, systemImage: "exclamationmark.triangle").font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 10) {
                Label(content.mark, systemImage: content.markSymbol).font(.caption).foregroundStyle(.secondary)
                    .help(content.markDetail)
                Spacer(minLength: 8)
                if let button = content.button {
                    Button(button, action: act).cardButtons().buttonStyle(.borderedProminent).disabled(content.state.isBusy)
                }
            }
            checkLine
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }

    @ViewBuilder private var checkLine: some View {
        switch content.state {
        case .idle: EmptyView()
        case .checking: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking \(content.device)…").foregroundStyle(.secondary) }
        case .working(let words): HStack(spacing: 6) { ProgressView().controlSize(.small); Text(words).foregroundStyle(.secondary) }
        case .waiting(let words): HStack(spacing: 6) { ProgressView().controlSize(.small); Text(words).foregroundStyle(.secondary) }
        case .failed(let words): Label(words, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension DeviceStepCard.Content {
    /// A step's card from its data, with Lamp's values filled into what it shows.
    init(step: Integration.Step, number: Int, of total: Int, device: String, values: [String: String], state: DeviceStepCard.State) {
        func filled(_ template: String) -> String { (try? Placeholders.fill(template, values, in: .shown)) ?? "Not known yet" }
        let mark = IntegrationWords.mark(step.known)
        let signIn = step.run?.compactMap { $0.vendorSignIn }.first.flatMap { VendorSignIn.domain(of: $0.page) }
        let button: String? = signIn.map { "Sign In on \($0)…" }
            ?? (step.field != nil ? "Continue" : step.run?.isEmpty == false ? "Continue" : step.wait == true ? "Check Now" : "Check")
        self.init(device: device, number: number, of: total, title: step.title, lines: step.lines ?? [],
                  shown: (step.show ?? []).map { Shown(label: $0.label, value: filled($0.value)) },
                  qr: step.qr.map(filled), field: step.field.map { Field(label: $0.label, secret: $0.secret ?? true) },
                  link: step.link.flatMap(URL.init(string:)), signIn: signIn,
                  accepts: (step.accepts ?? []).map { IntegrationWords.accepts($0, device: device) },
                  mark: mark.title, markSymbol: mark.symbol, markDetail: IntegrationWords.markDetail(step.known),
                  button: button, state: state)
    }
}

/// A device whose certificate isn't the one Lamp kept: what happened, what the person accepts by reconnecting, and the
/// one button. Lamp keeps the certificate a device first shows so nothing else on the network can pose as it and be sent
/// its password; resetting a device, or turning its developer mode on again, gives it a new one, which only the person
/// can tell from an impostor.
struct DeviceReconnectCard: View {
    let device: String
    let reconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(device) looks different").font(.headline)
            Text("Lamp knows \(device) by the certificate it first showed. It shows another now, which happens when it's reset or its developer mode is turned on again.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("What you accept").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Label("Lamp will trust the device at this address from now on. Do this only if you changed \(device) yourself.",
                      systemImage: "exclamationmark.triangle").font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Reconnect", action: reconnect).cardButtons().buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }
}

/// A command for the device, or a tool for this Mac, the first time it runs on a device: the command, what it's for
/// in the integration's words, and what the person accepts in Lamp's. Allowed, that exact text runs on that device from
/// then on without asking; changed, it asks again.
struct DeviceCommandCard: View {
    let approval: DeviceCommandApproval
    let allow: () -> Void
    let deny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(approval.title).font(.headline)
            Text(approval.explanation).fixedSize(horizontal: false, vertical: true)
            Text(approval.command).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            Label(approval.accepts, systemImage: "exclamationmark.triangle").font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Don't Allow", action: deny).cardButtons()
                Button("Allow", action: allow).cardButtons().buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }
}

// MARK: - In the chat

/// The device's next step in a wish's chat, when the wish needs it set up: a line with Set Up…, which opens the setup
/// window (`DeviceSetupWindow`) with the step's card. Once the device is set up it says so.
enum DeviceStepLine {
    /// The line the chat shows for it: the card's own controls are in the setup window.
    @MainActor static func text(_ deviceID: String) -> (text: String, done: Bool) {
        guard let device = Store.shared.devices.first(where: { $0.id == deviceID }) ?? Integrations.kept(deviceID).map({ Integrations.device(from: $0, onNetwork: false) }) else {
            return ("Set up the device", false)
        }
        if let step = Integrations.next(for: device) { return ("Set up \(device.name): \(step.title.lowercased())", false) }
        return ("\(device.name) is set up", true)
    }
}


/// A set-up device's test run: Lamp puts a test app on it, tries it, and takes it off (`IntegrationProbe`). Each stage
/// ticks as it goes, with the device's words where one failed; a run that passed leaves the bridge's mark.
struct DeviceTrialCard: View {
    let device: String
    let stages: [IntegrationProbe.Stage]
    let worked: String?
    let enabled: Bool
    let tryIt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lamp puts a test app on \(device), tries it with the remote, then takes it off.").foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !stages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(stages) { stage in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            symbol(stage.state).frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stage.id).opacity(stage.state == .skipped || stage.state == .waiting ? 0.5 : 1)
                                if case .failed(let why) = stage.state { Text(why).font(.callout).foregroundStyle(.secondary).lineLimit(4) }
                            }
                        }
                    }
                }
            }
            HStack {
                if let worked { Label(worked, systemImage: "checkmark.seal").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button(stages.isEmpty ? "Try It on \(device)" : "Try Again", action: tryIt).disabled(!enabled)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func symbol(_ state: IntegrationProbe.Stage.State) -> some View {
        switch state {
        case .running: ProgressView().controlSize(.small)
        case .passed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .waiting, .skipped: Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
}
