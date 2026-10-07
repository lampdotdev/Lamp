import SwiftUI
import AppKit

/// A handoff can take a while (Xcode's download or a phone update). Keep a small window open and recheck
/// when the person returns; don't hold a build or a chat message open while they finish Apple's setup.
@MainActor
final class PhoneSetup: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PhoneSetup()
    @Published private(set) var checking = false
    @Published private(set) var report: PhoneTools.Report?
    @Published var actionProblem: String?
    private var family: DeviceFamily = .iphone
    private var phone: String?
    private var continuation: (() -> Void)?
    private var window: NSWindow?
    private var request = UUID()

    func show(family: DeviceFamily = .iphone, phone: String? = nil) {
        guard !checking else { window?.makeKeyAndOrderFront(nil); return }
        self.family = family
        self.phone = phone
        continuation = nil
        present()
        refresh()
    }

    func perform(family: DeviceFamily = .iphone, phone: String? = nil, eitherSimulator: Bool = false, then: @escaping () -> Void) {
        guard !checking else { window?.makeKeyAndOrderFront(nil); return }
        self.family = family
        self.phone = phone
        continuation = then
        let request = UUID()
        self.request = request
        check(eitherSimulator: eitherSimulator) { [weak self] in
            guard let self, self.request == request else { return }
            if report?.ready == true {
                continuation = nil
                window?.close()
                then()
            } else {
                present()
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if self.request == request, checking { present() }
        }
    }

    func perform(for project: LampProject, then: @escaping () -> Void) {
        guard project.platform == .iphone else { then(); return }
        perform(family: project.family, phone: Experiments.devices ? project.device : nil, then: then)
    }

    func refresh() { check {} }

    func refreshIfVisible() {
        if window?.isVisible == true { refresh() }
    }

    private func check(eitherSimulator: Bool = false, completed: @escaping () -> Void) {
        guard !checking else { return }
        checking = true
        actionProblem = nil
        let family = family, phone = phone
        Task {
            let result = await Task.detached {
                let preferred = PhoneTools.checked(family: family, phone: phone)
                if eitherSimulator, preferred.issue?.step == .simulator {
                    let other = PhoneTools.checked(family: family == .iphone ? .ipad : .iphone, phone: phone)
                    if other.ready { return other }
                }
                return preferred
            }.value
            report = result
            checking = false
            completed()
        }
    }

    func windowWillClose(_ notification: Notification) {
        continuation = nil
        request = UUID()
    }

    private func present() {
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

    func finish() {
        let next = continuation
        continuation = nil
        window?.close()
        next?()
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

extension PhoneSetup {
    func finishWithoutContinuing() {
        continuation = nil
        window?.close()
    }
}

@MainActor
extension Store {
    func createPhoneApp() { PhoneSetup.shared.perform(eitherSimulator: true) { self.create(platform: .iphone) } }
    func openPrepared(_ project: LampProject) {
        PhoneSetup.shared.perform(for: project) { Task { await self.open(project) } }
    }
    func runPrepared(_ project: LampProject) {
        PhoneSetup.shared.perform(for: project) { Task { await self.run(project) } }
    }
}
