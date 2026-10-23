import AppKit
import SwiftUI

/// Getting ready to put games on an Xbox: one window, like Android's (`AndroidSetup`), with the one download Lamp makes
/// (`WindowsTools.install`). Microsoft's part can't be passed on, so the person reads and accepts its licence here
/// before anything of Microsoft's is fetched; the box is theirs to check, and nothing downloads until they do. What
/// asked for the tools (the first time a game goes on an Xbox) waits until they're here, or is let go when the window
/// closes. The preview on the Mac never needs it.
@MainActor
final class WindowsSetup: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = WindowsSetup()

    @Published private(set) var installing: (part: Double, doing: String)?
    @Published var problem: String?
    @Published var accepted = WindowsTools.licenseAccepted
    @Published private(set) var ready = WindowsTools.isReady

    private var waiting: [(then: () -> Void, cancelled: () -> Void)] = []
    private var closingInternally = false
    private var window: NSWindow?

    func show() {
        ready = WindowsTools.isReady
        present()
    }

    /// Runs `then` once the tools are here: at once when they are, else after the window has got them; `cancelled`
    /// when the person closes the window instead.
    func perform(cancelled: @escaping () -> Void = {}, then: @escaping () -> Void) {
        ready = WindowsTools.isReady
        if ready { then(); return }
        waiting.append((then, cancelled))
        present()
    }

    var hasRequest: Bool { !waiting.isEmpty }

    func download() {
        guard installing == nil, accepted else { return }
        WindowsTools.licenseAccepted = true
        installing = (0, "Starting…")
        problem = nil
        Task {
            do {
                try await WindowsTools.install { part, doing in
                    Task { @MainActor in self.installing = (part, doing) }
                }
            } catch {
                problem = error.localizedDescription
            }
            installing = nil
            ready = WindowsTools.isReady
            if ready {
                let requests = waiting
                waiting.removeAll()
                if !requests.isEmpty { closeWindow() }
                requests.forEach { $0.then() }
            }
        }
    }

    func cancel() {
        let requests = waiting
        waiting.removeAll()
        closeWindow()
        requests.forEach { $0.cancelled() }
    }

    func windowWillClose(_ notification: Notification) {
        if !closingInternally { cancel() }
    }

    private func closeWindow() {
        closingInternally = true
        window?.close()
        closingInternally = false
    }

    private func present() {
        if window == nil {
            let content = NSHostingController(rootView: WindowsSetupView(model: self))
            content.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: content)
            window.styleMask = [.titled, .closable]
            window.delegate = self
            window.title = "Xbox Setup for Games"
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct WindowsSetupView: View {
    @ObservedObject var model: WindowsSetup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "gamecontroller").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary).frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Get ready to put games on your Xbox").font(.title2.weight(.semibold))
                    Text(WindowsTools.supported
                         ? "Lamp builds games for the console with free tools from LLVM and Microsoft. They aren't on this Mac yet: about 1.7 GB to download, 1 GB kept."
                         : "Games are put on an Xbox with tools that run only on Macs with Apple silicon. They still play in the Xbox preview on this Mac.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 20)
            if WindowsTools.supported, !model.ready {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $model.accepted) {
                        Text("I accept the license terms for Microsoft's Windows SDK and C runtime")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(model.installing != nil || WindowsTools.licenseAccepted)
                    Link("Read the license terms", destination: WindowsTools.licenseURL).font(.callout).padding(.leading, 20)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            if let installing = model.installing {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: installing.part)
                    Text(installing.doing).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, 16)
            }
            if model.ready {
                Label("Everything's ready.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }
            HStack(spacing: 10) {
                Spacer()
                if model.ready {
                    Button("Done") { model.cancel() }.keyboardShortcut(.defaultAction)
                } else {
                    Button(model.hasRequest ? "Cancel" : "Close") { model.cancel() }.keyboardShortcut(.cancelAction)
                    if WindowsTools.supported {
                        Button("Download") { model.download() }.keyboardShortcut(.defaultAction)
                            .disabled(!model.accepted || model.installing != nil)
                    }
                }
            }
            .padding(.top, 20)
        }
        .padding(20)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}
