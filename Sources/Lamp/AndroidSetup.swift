import Combine
import AppKit
import SwiftUI

/// Getting ready for Android apps: one window, like the iPhone's (`PhoneSetup`), that checks what's missing and
/// does the next thing itself. Google's tools are a download Lamp makes (`AndroidTools.install`), shown with its
/// progress; a device of the person's is theirs to plug in and allow. What asked for the check (a request, Play)
/// waits until the window finds everything there, or is let go when the window closes.
@MainActor
final class AndroidSetup: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = AndroidSetup()

    @Published private(set) var checking = false
    @Published private(set) var report: AndroidTools.Report?
    @Published private(set) var installing: (part: Double, doing: String)?
    @Published var problem: String?

    private struct Request {
        let device: String?
        let then: () -> Void
        let cancelled: () -> Void
    }
    private var active: Request?
    private var pending: [Request] = []
    private var device: String?
    private var presented = false
    private var closingInternally = false
    private var window: NSWindow?
    private var resizing: AnyCancellable?

    /// Shows the window for a look, nothing waiting on it.
    func show(device: String? = nil) {
        if active == nil, pending.isEmpty { self.device = device }
        present()
        refresh()
    }

    /// Runs `then` once everything an Android app needs is there (`device`: the person's own, when one is chosen),
    /// at once when it already is, else after the window has walked the person through it; `cancelled` when they
    /// close the window instead.
    func perform(device: String?, cancelled: @escaping () -> Void = {}, then: @escaping () -> Void) {
        pending.append(Request(device: device, then: then, cancelled: cancelled))
        startNext()
    }

    private func startNext() {
        guard !checking, active == nil, !pending.isEmpty else { return }
        active = pending.removeFirst()
        device = active?.device
        refresh()
    }

    /// `keepingProblem`: after a download that failed, the reason stays on screen through the look at what's there.
    func refresh(keepingProblem: Bool = false) {
        guard !checking, installing == nil else { return }
        checking = true
        if !keepingProblem { problem = nil }
        let device = self.device
        Task {
            let result = await AndroidTools.check(device: device)
            checking = false
            report = result
            if result.ready, let request = active {
                active = nil
                if pending.isEmpty { closeWindow() }
                request.then()
                startNext()
            } else if active != nil {
                present()
            } else {
                // A look of the person's own: a request that arrived while it ran gets a check of its own now.
                startNext()
            }
        }
    }

    /// The next step's button: a download Lamp makes, or a look again after the person did their part.
    func act() {
        guard let issue = report?.issue, installing == nil else { return }
        switch issue.action {
        case .retry: refresh()
        case .download:
            installing = (0, "Starting…")
            problem = nil
            Task {
                do {
                    try await AndroidTools.install { part, doing in
                        Task { @MainActor in self.installing = (part, doing) }
                    }
                } catch {
                    problem = error.localizedDescription
                }
                let failed = problem != nil
                installing = nil
                refresh(keepingProblem: failed)
            }
        }
    }

    var hasRequest: Bool { active != nil }

    func cancel() {
        let request = active
        active = nil
        let waiting = pending
        pending.removeAll()
        closeWindow()
        request?.cancelled()
        for other in waiting { other.cancelled() }
    }

    func windowWillClose(_ notification: Notification) {
        presented = false
        if !closingInternally { cancel() }
    }

    private func closeWindow() {
        presented = false
        closingInternally = true
        window?.close()
        closingInternally = false
    }

    private func present() {
        presented = true
        if window == nil {
            let (window, resizing) = FittedWindow.make(AndroidSetupView(model: self), following: objectWillChange)
            self.resizing = resizing
            window.delegate = self
            window.title = "Android Setup"
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

/// The checks as the person would recognize them, each a row: the tools, the emulator, and their device when one is
/// chosen.
struct AndroidSetupView: View {
    @ObservedObject var model: AndroidSetup

    private var steps: [AndroidTools.Step] {
        AndroidTools.Step.allCases.filter { step in
            step != .device || model.report?.passed.contains(.device) == true || model.report?.issue?.step == .device
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "smartphone").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary).frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Get ready for Android").font(.title2.weight(.semibold))
                    Text("Lamp needs a few things from Google before it can make Android apps. Here's what's done and what's next.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                    if index > 0 { Divider().padding(.leading, 44) }
                    row(step)
                }
            }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            if let installing = model.installing {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: installing.part)
                    Text(installing.doing).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, 16)
            }
            if model.report?.ready == true {
                Text(model.report?.passed.contains(.device) == true ? "Everything's ready, your Android device included."
                     : "Everything's ready. To put an app on your own Android phone or tablet, plug it in with USB debugging on and choose it under Try On.")
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
            }
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }
            footer.padding(.top, 20)
        }
        .padding(20)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func name(_ step: AndroidTools.Step) -> (String, String) {
        switch step {
        case .tools: return ("Android's tools", "Google's free tools for making Android apps")
        case .emulator: return ("Emulator", "An Android phone on your Mac's screen, where Lamp tries your app")
        case .device: return ("Your Android device", "Plugged in, with USB debugging allowed to this Mac")
        }
    }

    @ViewBuilder
    private func row(_ step: AndroidTools.Step) -> some View {
        let passed = model.report?.passed.contains(step) == true
        let issue = model.report?.issue.flatMap { $0.step == step ? $0 : nil }
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
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(step).0).fontWeight(.medium)
                    Text(name(step).1).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .opacity(passed ? 1 : 0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            let issue = model.report?.issue
            let ready = model.report?.ready == true
            if model.checking {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            } else if issue != nil, issue?.action != .retry, model.installing == nil {
                Button("Check Again") { model.refresh() }
            }
            Spacer()
            if !ready || model.hasRequest {
                Button(model.hasRequest ? "Cancel" : "Close") { model.cancel() }.keyboardShortcut(.cancelAction)
            }
            if let issue {
                Button(issue.button) { model.act() }.keyboardShortcut(.defaultAction).disabled(model.checking || model.installing != nil)
            } else if ready {
                Button("Done") { model.cancel() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
