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
            return Context(family: current.family, phone: Experiments.devices ? current.device : nil)
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
        if request != nil {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                if generation == ticket, active?.id == request?.id, checking { present() }
            }
        }
    }

    func refreshIfVisible() { if presented { refresh() } }

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
            actionProblem = "This app is still changing. Wait for it to finish, then press Continue."
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.delegate = self
            window.title = "iPhone & iPad Setup"
            window.contentView = NSHostingView(rootView: PhoneSetupView(model: self))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
            guard let developer = report?.developer else { return }
            open(URL(fileURLWithPath: developer + "/Applications/Simulator.app"))
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
            actionProblem = "Choose Apple's full Xcode app."
            return
        }
        PhoneTools.use(developer)
        refresh()
    }

    private func open(_ url: URL) {
        if !NSWorkspace.shared.open(url) { actionProblem = "Couldn't open it. Please open it yourself, then come back and check again." }
    }
}

struct PhoneSetupView: View {
    @ObservedObject var model: PhoneSetup

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Get ready to build for iPhone & iPad", systemImage: "iphone")
                .font(.title2).fontWeight(.semibold)
            Text("Lamp checks each step before you start building.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(PhoneTools.Step.allCases.filter { $0 != .phone || model.report?.passed.contains(.phone) == true || model.report?.issue?.step == .phone }, id: \.self) { step in
                    let passed = model.report?.passed.contains(step) == true
                    let failed = model.report?.issue?.step == step
                    Label(step.rawValue, systemImage: passed ? "checkmark.circle.fill" : failed ? "exclamationmark.circle.fill" : "circle")
                        .foregroundStyle(passed ? Color.green : failed ? Color.orange : Color.secondary)
                }
            }
            if model.checking {
                HStack { ProgressView().controlSize(.small); Text("Checking your setup…") }
            } else if let issue = model.report?.issue {
                VStack(alignment: .leading, spacing: 8) {
                    Text(issue.title).font(.headline)
                    Text(issue.message).fixedSize(horizontal: false, vertical: true)
                    Button(issue.button) { model.act() }.buttonStyle(.borderedProminent)
                    if issue.step == .xcode || issue.step == .tools {
                        Button("Choose Xcode…") { model.chooseXcode() }
                    }
                }
            } else if model.report != nil {
                Text(model.report?.passed.contains(.phone) == true
                     ? "The building tools and your phone's software are ready."
                     : "The building tools are ready. To use your own phone, choose it under Try On; Lamp will check its software version too.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Continue") { model.finish() }.buttonStyle(.borderedProminent)
            }
            if let problem = model.actionProblem { Text(problem).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 0)
            HStack {
                Button("Close") { model.finishWithoutContinuing() }
                Spacer()
                Button("Check Again") { model.refresh() }.disabled(model.checking)
            }
        }
        .padding(24)
        .frame(width: 540, height: 640)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshIfVisible()
        }
    }
}

@MainActor
extension Store {
    func createPhoneApp() { PhoneSetup.shared.perform(eitherSimulator: true) { self.create(platform: .iphone) } }
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
