import Combine
import AppKit
import SwiftUI

/// Setting up one TV, step by step, in a window of its own: each step checked by Lamp, the next one shown with what to
/// do on the TV's remote or the one button that does it from here. Samsung: developer mode pointed at this Mac, a
/// connection, and Samsung's permission for this Mac's apps (a sign-in, once). LG: Developer Mode with its key server
/// on, and the passphrase it shows. What asked for the setup (Play) goes on once it's done.
@MainActor
final class TVSetup: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = TVSetup()

    @Published private(set) var record: TVs.Record?
    @Published private(set) var working: String?
    @Published var problem: String?
    @Published var passphrase = ""
    private var window: NSWindow?
    private var resizing: AnyCancellable?
    private var waiting: (() -> Void)?
    /// Which TV the window is for now: work started for another (a check, a connection, a sign-in) that ends after
    /// the person moved on is dropped, so its result can't stand for this TV or resume its Play.
    private var selection = UUID()
    /// Do It for Me: the steps of the skill that says it does this TV's next step on its system, run for this TV.
    let guided = GuidedSetup()
    private var following: AnyCancellable?

    override init() {
        super.init()
        following = guided.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// By the names a setup guide gives them (`setup-step`).
    enum Step: String, CaseIterable { case developerMode = "developer-mode", connected, permission }

    /// Where the TV's setup stands: the steps done, and the next one.
    var passed: [Step] {
        guard let record else { return [] }
        var steps: [Step] = []
        if record.isSamsung {
            guard record.developerMode, TVs.macAddresses().contains(record.developerIP ?? "") else { return steps }
            steps.append(.developerMode)
            guard let duid = record.duid else { return steps }
            steps.append(.connected)
            if TizenSigning.hasCertificates(for: duid) { steps.append(.permission) }
        } else if FileManager.default.fileExists(atPath: WebOS.keyURL(record.id).path) {
            steps += [.developerMode, .connected, .permission]
        }
        return steps
    }
    var next: Step? { Step.allCases.first { !passed.contains($0) } }
    var ready: Bool { next == nil && record != nil }

    /// The steps Do It for Me follows for this TV's next step, when a skill does that step on its system and its
    /// steps can be followed. This window is the TV row's ("tv"), Samsung's and LG's alike: the system tells them apart.
    var guide: SetupSteps? {
        guard let record, let next,
              case .success(let steps)? = SetupGuides.find(next.rawValue, in: .init(row: "tv", system: record.os, steps: Set(Step.allCases.map(\.rawValue))))
        else { return nil }
        return steps
    }

    func doItForMe() {
        guard let record, let next, let steps = guide, working == nil else { return }
        problem = nil
        let (address, id) = (record.address, record.id)
        guided.start(steps, name: record.name, step: next.rawValue,
                     connect: { SetupConnections.socket(steps.connection, address: address, id: id) },
                     onFinish: { [weak self] in Task { await self?.refresh() } })
    }

    /// Back to the steps in words: the guide stops, and the TV's own step (the passphrase and Connect) is the person's.
    func doItMyself() { guided.cancel() }

    func show(_ id: String, then: (() -> Void)? = nil) {
        if record?.id != id { guided.cancel() }
        if record?.id != id || working == nil { selection = UUID() }
        record = TVs.record(id)
        waiting = then
        problem = nil
        passphrase = ""
        present()
        Task { await refresh() }
    }

    /// Runs `then` at once when the TV is ready, else shows its setup and runs it once it is.
    func perform(_ id: String, then: @escaping () -> Void) {
        let record = TVs.record(id)
        if let record, Device.from(tv: record, onNetwork: true, kept: TVs.kept().contains { $0.id == id }).setup() == .ready { then(); return }
        show(id, then: then)
    }

    /// Asks the TV again where it stands (its developer mode is read off its own API).
    func refresh() async {
        guard let current = record else { return }
        let ticket = selection
        let found = current.isSamsung ? await TVs.samsung(at: current.address) : current
        guard ticket == selection else { return }
        guard var updated = found else { problem = "\(current.name) isn't answering on the network. Turn it on, then Check Again."; return }
        updated.id = current.id
        updated.duid = current.duid ?? TVs.kept().first { $0.id == current.id }?.duid
        if !updated.osVersion.isEmpty || current.osVersion.isEmpty { } else { updated.osVersion = current.osVersion }
        record = updated
        if TVs.kept().contains(where: { $0.id == updated.id }) { TVs.keep(updated) }
        dropFinishedGuide()
        if ready { finish() }
    }

    func act() {
        guard let record, let next, working == nil else { return }
        problem = nil
        switch (record.isSamsung, next) {
        case (true, .developerMode):
            Task { await refresh() }
        case (true, .connected):
            run("Connecting to \(record.name)…") { try await TVs.connectSamsung(record) }
        case (true, .permission):
            guard let duid = record.duid else { return }
            run("Waiting for you to sign in to Samsung in your browser…") { try await TizenSigning.signInAndCertify(duid: duid); return nil }
        case (false, _):
            let code = passphrase.trimmingCharacters(in: .whitespaces)
            guard code.count >= 4 else { problem = "Enter the passphrase the Developer Mode app shows on the TV."; return }
            run("Connecting to \(record.name)…") { try await WebOS.connect(record, passphrase: code) }
        }
    }

    /// Runs a step's work; what it comes back with stands for the TV only while the window is still on that TV.
    private func run(_ doing: String, _ work: @escaping () async throws -> TVs.Record?) {
        working = doing
        let ticket = selection
        Task {
            var failed = false
            do {
                let updated = try await work()
                if ticket == selection, let updated { record = updated }
            } catch {
                failed = true
                if ticket == selection { problem = error.localizedDescription }
            }
            working = nil
            dropFinishedGuide()
            objectWillChange.send()
            Store.shared.refreshDevices()
            if ticket == selection, !failed, ready { finish() }
        }
    }

    /// A guide that handed the TV back stays on screen only while the step it was for is still the one to do.
    private func dropFinishedGuide() {
        if guided.handedBack, guided.step != next?.rawValue { guided.cancel() }
    }

    private func finish() {
        let then = waiting
        waiting = nil
        then?()
    }

    func close() {
        waiting = nil
        window?.close()
    }

    /// Closed with its own button or the title bar's: what was waiting for this TV (Play) doesn't go ahead later.
    func windowWillClose(_ notification: Notification) {
        guided.cancel()
        waiting = nil
        selection = UUID()
    }

    private func present() {
        if window == nil {
            let (window, resizing) = FittedWindow.make(TVSetupView(model: self), following: objectWillChange)
            self.resizing = resizing
            window.delegate = self
            window.center()
            self.window = window
        }
        window?.title = record.map { "Set Up \($0.name)" } ?? "TV Setup"
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct TVSetupView: View {
    @ObservedObject var model: TVSetup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "tv").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary).frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.record.map { "Set up \($0.name)" } ?? "Set up a TV").font(.title2.weight(.semibold))
                    Text(model.record.map { "\($0.maker) \($0.model)" + ($0.osVersion.isEmpty ? "" : " · \($0.os) \($0.osVersion)") } ?? "")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(TVSetup.Step.allCases.enumerated()), id: \.element) { index, step in
                    if index > 0 { Divider().padding(.leading, 44) }
                    row(step)
                }
            }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            if let working = model.working {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(working).foregroundStyle(.secondary) }.padding(.top, 14)
            }
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }
            if model.ready, let record = model.record {
                Text("\(record.name) is ready. Choose it under Try On in a TV app and press Play.").padding(.top, 16)
            }
            HStack {
                Spacer()
                Button(model.ready ? "Done" : "Close") { model.close() }.keyboardShortcut(model.ready ? .defaultAction : .cancelAction)
                if let label = buttonLabel {
                    Button(label) { model.act() }.keyboardShortcut(.defaultAction)
                        .disabled(model.working != nil || model.guided.running)
                }
            }
            .padding(.top, 20)
        }
        .padding(20)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var buttonLabel: String? {
        guard let record = model.record, let next = model.next else { return nil }
        if !record.isSamsung { return "Connect" }
        switch next {
        case .developerMode: return "Check Again"
        case .connected: return "Connect"
        case .permission: return "Sign In to Samsung…"
        }
    }

    private func title(_ step: TVSetup.Step, samsung: Bool) -> String {
        switch step {
        case .developerMode: return samsung ? "Developer mode" : "Developer Mode"
        case .connected: return samsung ? "Connected" : "This Mac let in"
        case .permission: return samsung ? "Samsung's permission" : "Ready for apps"
        }
    }

    private func instructions(_ step: TVSetup.Step, record: TVs.Record) -> String {
        let mac = TVs.macAddresses().first ?? "this Mac's address"
        if record.isSamsung {
            switch step {
            case .developerMode:
                return "On the TV, open Apps and press 1 2 3 4 5 on the remote. Turn Developer mode on, enter \(mac) as the address, and choose OK. Then turn the TV off and on again with the remote, and click Check Again."
            case .connected:
                return "Lamp connects to the TV to read what it needs, such as its version of Tizen."
            case .permission:
                return "Samsung lets your own apps onto a TV with a certificate from a Samsung account (free). Lamp opens Samsung's sign-in in your browser; sign in there, and Lamp does the rest."
            }
        }
        return "On the TV, install Developer Mode from the LG Content Store and sign in to it with an LG developer account (free, from LG's developer site). Turn Dev Mode Status on and let the TV restart, then open Developer Mode again and turn Key Server on. Enter the passphrase it shows here."
    }

    @ViewBuilder
    private func row(_ step: TVSetup.Step) -> some View {
        let passed = model.passed.contains(step)
        let current = model.next == step
        let samsung = model.record?.isSamsung ?? true
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: passed ? "checkmark.circle.fill" : current ? "arrow.forward.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(passed ? AnyShapeStyle(Color.green) : current ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 6) {
                Text(title(step, samsung: samsung)).font(current ? .headline : .body).fontWeight(current ? .semibold : .medium)
                if current, let record = model.record {
                    if model.guided.started {
                        SetupGuideView(state: model.guided.state, confirm: { model.guided.confirm() }, retry: { model.guided.retry() },
                                       doItMyself: model.guided.handedBack ? nil : { model.doItMyself() })
                    } else {
                        Text(instructions(step, record: record)).fixedSize(horizontal: false, vertical: true)
                        if let guide = model.guide {
                            DoItForMeRow(offer: guide.offer, start: { model.doItForMe() }).disabled(model.working != nil)
                        }
                    }
                    if !samsung, !model.guided.running {
                        TextField("Passphrase", text: $model.passphrase).textFieldStyle(.roundedBorder).frame(width: 160)
                    }
                }
            }
            .opacity(passed || current ? 1 : 0.6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}
