import Combine
import SwiftUI
import AppKit

/// Setup can outlast a download or phone update. Keep each requested action until its own checks pass
/// or the person closes setup, and resolve the app again before applying a deferred change.
@MainActor
final class PhoneSetup: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PhoneSetup()
    struct Context: Equatable {
        var family: DeviceFamily = .iphone
        var phone: String?
        var eitherSimulator = false
        var requiresPhoneTools = true
    }
    private struct Request {
        let id = UUID()
        let resolve: () -> Context?
        let then: () -> Void
        let cancelled: () -> Void
        let isReady: () -> Bool
        var waiting = false
    }

    @Published private(set) var checking = false
    @Published private(set) var report: PhoneTools.Report?
    @Published var actionProblem: String?
    private var active: Request?
    private var pending: [Request] = []
    private var inspection = Context()
    private var checkedContext: Context?
    private var generation = UUID()
    private var presented = false
    private var closingInternally = false
    private let presentsWindow: Bool
    private let inspect: (Context) async -> PhoneTools.Report
    private var window: NSWindow?

    init(presentsWindow: Bool = true, inspect: @escaping (Context) async -> PhoneTools.Report = PhoneSetup.inspect) {
        self.presentsWindow = presentsWindow
        self.inspect = inspect
        super.init()
    }

    nonisolated private static func inspect(_ context: Context) async -> PhoneTools.Report {
        await Task.detached {
            let preferred = PhoneTools.checked(family: context.family, phone: context.phone)
            if context.eitherSimulator, preferred.issue?.step == .simulator {
                let other = PhoneTools.checked(family: context.family == .iphone ? .ipad : .iphone, phone: context.phone)
                if other.ready { return other }
            }
            return preferred
        }.value
    }

    func show(family: DeviceFamily = .iphone, phone: String? = nil) {
        if active == nil && pending.isEmpty { inspection = Context(family: family, phone: phone) }
        present()
        refresh()
    }

    func perform(family: DeviceFamily = .iphone, phone: String? = nil, eitherSimulator: Bool = false,
                 cancelled: @escaping () -> Void = {}, then: @escaping () -> Void) {
        perform(resolve: { Context(family: family, phone: phone, eitherSimulator: eitherSimulator) }, cancelled: cancelled, then: then)
    }

    func perform(resolve: @escaping () -> Context?, cancelled: @escaping () -> Void = {},
                 isReady: @escaping () -> Bool = { true }, then: @escaping () -> Void) {
        pending.append(Request(resolve: resolve, then: then, cancelled: cancelled, isReady: isReady))
        startNext()
    }

    func perform(for project: LampProject, in store: Store, cancelled: @escaping () -> Void = {},
                 then: @escaping (LampProject) -> Void) {
        guard let current = store.current(project) else { cancelled(); return }
        guard current.platform == .iphone else { then(current); return }
        perform(resolve: {
            guard let current = store.current(project) else { return nil }
            return Context(family: current.family, phone: current.device,
                           requiresPhoneTools: current.platform == .iphone)
        }, cancelled: cancelled) {
            if let current = store.current(project) { then(current) }
            else { cancelled() }
        }
    }

    private func startNext() {
        guard !checking, active == nil, !pending.isEmpty else { return }
        active = pending.removeFirst()
        refresh()
    }

    func refresh() {
        guard !checking else { return }
        let request = active
        let context: Context
        if let request {
            guard let resolved = request.resolve() else { cancelActive(); return }
            context = resolved
        } else {
            context = inspection
        }
        if !context.requiresPhoneTools {
            report = PhoneTools.Report()
            checkedContext = context
            actionProblem = nil
            completeActive()
            return
        }
        checking = true
        actionProblem = nil
        checkedContext = context
        let ticket = generation
        Task {
            let result = await inspect(context)
            checking = false
            guard generation == ticket else { startNext(); if active == nil && presented { refresh() }; return }
            if let request {
                guard active?.id == request.id else { startNext(); return }
                guard let current = request.resolve() else { cancelActive(); return }
                guard current == context else { refresh(); return }
                report = result
                if result.ready && !request.waiting { completeActive() }
                else { active?.waiting = true; present() }
            } else {
                // An action submitted during an automatic recheck still gets its own context and result.
                if !pending.isEmpty { startNext(); return }
                guard context == inspection else { refresh(); return }
                report = result
            }
        }
        // A check that drags on (a first look at Xcode, a phone to wake) shows its window with the progress;
        // the usual one, under a second before every run of an iPhone app, must not flash one open and shut.
        if request != nil {
            Task {
                try? await Task.sleep(for: .seconds(3))
                if generation == ticket, active?.id == request?.id, checking { present() }
            }
        }
    }

    func refreshIfVisible() { if presented { refresh() } }

    /// Whether something is waiting on this setup (a new app, a send, a run), so closing the window cancels it.
    var hasRequest: Bool { active != nil }

    func finish() {
        guard !checking, report?.ready == true else { return }
        guard let active else { closeWindow(); return }
        guard let current = active.resolve() else { cancelActive(); return }
        guard current == checkedContext else { refresh(); return }
        completeActive()
    }

    private func completeActive() {
        guard let request = active else { return }
        guard request.isReady() else {
            active?.waiting = true
            actionProblem = "Lamp is still working on this app. When it has finished, click Continue."
            present()
            return
        }
        active = nil
        if pending.isEmpty { closeWindow() }
        request.then()
        startNext()
    }

    private func cancelActive() {
        let request = active
        active = nil
        if pending.isEmpty { closeWindow() }
        request?.cancelled()
        startNext()
    }

    func finishWithoutContinuing() {
        cancelAll()
        closeWindow()
    }

    private func cancelAll() {
        generation = UUID()
        let requests = active.map { [$0] } ?? []
        active = nil
        let waiting = pending
        pending.removeAll()
        for request in requests + waiting { request.cancelled() }
    }

    func windowWillClose(_ notification: Notification) {
        presented = false
        if !closingInternally { cancelAll() }
    }

    private func closeWindow() {
        presented = false
        closingInternally = true
        window?.close()
        closingInternally = false
    }

    private func present() {
        presented = true
        guard presentsWindow else { return }
        if window == nil {
            // The window is as tall as what it says: the next step's instructions run from two lines to six.
            // Its size is set from the content by hand, after each change, rather than left to AppKit's
            // constraints: a window whose frame follows its content's constraints changes size in the middle
            // of a layout pass, and on macOS 26 the SwiftUI content then asks for another, which AppKit
            // answers with an exception (that crashed Lamp when the window appeared for a new iPhone app).
            let content = NSHostingController(rootView: PhoneSetupView(model: self))
            content.sizingOptions = []
            let window = NSWindow(contentViewController: content)
            window.styleMask = [.titled, .closable]
            window.delegate = self
            window.title = "iPhone & iPad Setup"
            window.isReleasedWhenClosed = false
            self.window = window
            fit()
            window.center()
            resizing = objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.fit() } }
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private var resizing: AnyCancellable?

    /// The window takes the size its content wants now. Called between layout passes, never inside one.
    private func fit() {
        guard let window, let controller = window.contentViewController as? NSHostingController<PhoneSetupView> else { return }
        // What the content would like, asked of SwiftUI directly: the hosting view's own fitting size is
        // nothing until it has been drawn once.
        let size = controller.sizeThatFits(in: NSSize(width: 10_000, height: 10_000))
        guard size.width > 0, size.height > 0, size != window.contentView?.frame.size else { return }
        let top = window.frame.maxY
        window.setContentSize(size)
        window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
    }

    func act() {
        guard let issue = report?.issue else { return }
        switch issue.action {
        case .installXcode:
            open(URL(string: "macappstore://itunes.apple.com/app/id497799835")!)
        case .useXcode:
            guard let developer = report?.developer else { return }
            PhoneTools.use(developer)
            refresh()
        case .openXcode, .components:
            guard let developer = report?.developer else { return }
            open(URL(fileURLWithPath: developer).deletingLastPathComponent().deletingLastPathComponent())
        case .simulator:
            Task { await Simulator.show() }
        case .settings:
            UserDefaults.standard.set("building", forKey: "settingsTab")
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .updatePhone:
            open(URL(string: "https://support.apple.com/118575")!)
        case .retry:
            refresh()
        }
    }

    func chooseXcode() {
        let panel = NSOpenPanel()
        panel.title = "Choose Xcode"
        panel.message = "Choose the Xcode app you want Lamp to use."
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let app = panel.url else { return }
        let developer = app.appendingPathComponent("Contents/Developer").path
        guard PhoneTools.isXcode(developer) else {
            actionProblem = "That isn't Xcode. Choose the app named Xcode."
            return
        }
        PhoneTools.use(developer)
        refresh()
    }

    private func open(_ url: URL) {
        if !NSWorkspace.shared.open(url) { actionProblem = "Lamp couldn't open that. Open it yourself, then come back and click Check Again." }
    }
}

/// The checks as the few things a person would recognize, each with what it is. The detector's steps sit
/// behind them: which agreement or download is missing is said in the step's own instructions.
private enum PhoneSetupStage: CaseIterable {
    case xcode, software, simulator, account, phone

    var steps: [PhoneTools.Step] {
        switch self {
        case .xcode: return [.xcode, .tools, .firstLaunch]
        case .software: return [.platform, .runtime]
        case .simulator: return [.simulator]
        case .account: return [.account]
        case .phone: return [.phone]
        }
    }
    var name: String {
        switch self {
        case .xcode: return "Xcode"
        case .software: return "iOS for Xcode"
        case .simulator: return "Simulator"
        case .account: return "Your Apple Account"
        case .phone: return "Your iPhone or iPad"
        }
    }
    var about: String {
        switch self {
        case .xcode: return "Apple's free app for making apps"
        case .software: return "What Xcode needs to make iPhone and iPad apps"
        case .simulator: return "An iPhone or iPad on your Mac's screen, where Lamp tries your app"
        case .account: return "Signed in to Xcode, with the team that signs apps for your phone"   // only shown once it has passed
        case .phone: return "On iOS \(PhoneTools.minimumIOS) or later"   // only shown once it has passed
        }
    }

    /// The account and the phone are only checked when a phone is chosen, so their rows only show then.
    var needsPhone: Bool { self == .account || self == .phone }
}

struct PhoneSetupView: View {
    @ObservedObject var model: PhoneSetup

    private var stages: [PhoneSetupStage] {
        PhoneSetupStage.allCases.filter { stage in
            !stage.needsPhone || stage.steps.contains { model.report?.passed.contains($0) == true || model.report?.issue?.step == $0 }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "ipad.and.iphone")
                    .font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Get ready for iPhone and iPad").font(.title2.weight(.semibold))
                    Text("Lamp needs a few things from Apple before it can make iPhone and iPad apps. Here's what's done and what's next.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.element) { index, stage in
                    if index > 0 { Divider().padding(.leading, 44) }
                    row(stage)
                }
            }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            if model.report?.ready == true {
                Text(summary).fixedSize(horizontal: false, vertical: true).padding(.top, 16)
            }
            // A problem with the next step is said beside it; one with carrying on is said here.
            if model.report?.issue == nil, let problem = model.actionProblem { self.problem(problem).padding(.top, 12) }
            footer.padding(.top, 20)
        }
        .padding(20)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshIfVisible()
        }
    }

    @ViewBuilder
    private func row(_ stage: PhoneSetupStage) -> some View {
        let passed = stage.steps.allSatisfy { model.report?.passed.contains($0) == true }
        let issue = model.report?.issue.flatMap { stage.steps.contains($0.step) ? $0 : nil }
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: passed ? "checkmark.circle.fill" : issue != nil ? "arrow.forward.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(passed ? AnyShapeStyle(Color.green) : issue != nil ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .frame(width: 20)
                .accessibilityLabel(passed ? "Done" : issue != nil ? "Next" : "Not yet")
            if let issue {
                VStack(alignment: .leading, spacing: 6) {
                    Text(issue.title).font(.headline)
                    Text(issue.message).fixedSize(horizontal: false, vertical: true)
                    if issue.step == .xcode || issue.step == .tools {
                        HStack(spacing: 4) {
                            Text(issue.step == .tools ? "Want Lamp to use a different copy?" : "Already have it somewhere Lamp didn't look?")
                                .foregroundStyle(.secondary)
                            Button("Choose Xcode…") { model.chooseXcode() }.buttonStyle(.link).disabled(model.checking)
                        }
                        .font(.callout).padding(.top, 2)
                    }
                    if let problem = model.actionProblem { self.problem(problem).padding(.top, 2) }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stage.name).fontWeight(.medium)
                    Text(stage.about).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .opacity(passed ? 1 : 0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func problem(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }

    private var summary: String {
        if model.report?.passed.contains(.phone) == true { return "Everything's ready, your iPhone or iPad included." }
        // An app that became a Mac app while this was open: nothing was checked, and nothing needs to be.
        if model.report?.passed.isEmpty == true { return "This is a Mac app now, so there's nothing to set up." }
        return "Everything's ready. To put an app on your own iPhone or iPad, choose it under Try On, beside the Play button, and Lamp will check that too."
    }

    /// One button row, the way a Mac dialog has it: the next thing to do on the right, where Return presses it.
    private var footer: some View {
        HStack(spacing: 10) {
            let issue = model.report?.issue
            let ready = model.report?.ready == true
            if model.checking {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            } else if issue != nil, issue?.action != .retry {
                Button("Check Again") { model.refresh() }
            }
            Spacer()
            // With nothing waiting on it and nothing left to do, there's only one way out of the window.
            if !ready || model.hasRequest {
                Button(model.hasRequest ? "Cancel" : "Close") { model.finishWithoutContinuing() }
                    .keyboardShortcut(.cancelAction)
            }
            if let issue {
                Button(issue.button) { model.act() }.keyboardShortcut(.defaultAction).disabled(model.checking)
            } else if ready {
                Button(model.hasRequest ? "Continue" : "Done") { model.finish() }
                    .keyboardShortcut(.defaultAction).disabled(model.checking)
            }
        }
    }
}

@MainActor
extension Store {
    func openPrepared(_ project: LampProject) {
        PhoneSetup.shared.perform(for: project, in: self) { current in Task { await self.open(current) } }
    }
    func choosePreparedDevice(_ project: LampProject, _ phone: String?) {
        PhoneSetup.shared.perform(resolve: {
            guard let current = self.current(project) else { return nil }
            return PhoneSetup.Context(family: current.family, phone: phone)
        }, isReady: {
            guard let current = self.current(project) else { return false }
            return !self.busy.contains(current.id)
        }) {
            if let current = self.current(project) { self.setDevice(current, phone) }
        }
    }

    func runPrepared(_ project: LampProject) {
        PhoneSetup.shared.perform(for: project, in: self) { current in Task { await self.run(current) } }
    }
}
