import SwiftUI
import AppKit

/// Hands the view's window over once it's in one.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowWatchView {
        let view = WindowWatchView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: WindowWatchView, context: Context) {
        view.onWindow = onWindow
    }
}

final class WindowWatchView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindow?(window) }
    }
}

/// A strip that moves the window when dragged and zooms it on a double-click, as a title bar does.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

// MARK: The window with no title bar

extension WebModel {
    /// The window keeps no title bar: the close, minimize and zoom buttons and a slim bar come in only while the
    /// pointer is at the top edge.
    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true
        window.tabbingMode = .disallowed
        window.title = site.name
        setChrome(barShown)

        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                self?.handleMouse(event)
                return event
            }
        }
        let center = NotificationCenter.default
        windowObservers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowResigned() }
        })
        windowObservers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowBecameKey() }
        })
        windowObservers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showBar(false) }
        })
    }

    func handleMouse(_ event: NSEvent) {
        guard let window, event.window === window, !window.styleMask.contains(.fullScreen) else { return }
        let fromTop = window.frame.height - event.locationInWindow.y
        if event.type == .mouseMoved { nudgeLights(nearTop: fromTop < 40) }
        if !barShown, fromTop <= 6 {
            showBar(true)
        } else if barShown, fromTop > 52, event.type == .mouseMoved {
            showBar(false)
        }
    }

    func windowResigned() {
        showBar(false)
        lightsTimer?.cancel()
        lightsShown = false
        setChrome(false)
    }

    /// Any movement of the pointer brings the window's buttons in; they fade again after a moment of stillness,
    /// unless the pointer rests near the top.
    func nudgeLights(nearTop: Bool) {
        lightsTimer?.cancel()
        if !lightsShown {
            lightsShown = true
            setChrome(true)
        }
        guard !nearTop else { return }
        let hide = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.fadeLights() } }
        lightsTimer = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: hide)
    }

    func fadeLights() {
        lightsShown = false
        setChrome(barShown)
    }

    func windowBecameKey() {
        setChrome(barShown)
        checkClipboard()
    }

    func showBar(_ shown: Bool) {
        guard shown != barShown else { return }
        withAnimation(.easeOut(duration: 0.16)) { barShown = shown }
        setChrome(shown || lightsShown)
    }

    /// The close, minimize and zoom buttons, in the title bar AppKit keeps hidden under the page.
    func setChrome(_ shown: Bool) {
        guard let container = window?.standardWindowButton(.closeButton)?.superview?.superview else { return }
        if standalone {
            // A site's own app is no longer Lamp's: it has no wand to customize it.
            func strip(_ view: NSView) {
                view.subviews.forEach { $0.identifier?.rawValue == "lampMagic" ? $0.removeFromSuperview() : strip($0) }
            }
            strip(container)
        }
        if shown {
            if container.isHidden {
                container.alphaValue = 0
                container.isHidden = false
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                container.animator().alphaValue = 1
            }
        } else if !container.isHidden {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                container.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                // Hidden once faded, so clicks at the top reach the page; unless it came back meanwhile.
                MainActor.assumeIsolated {
                    if self?.lightsShown == false, self?.barShown == false { container.isHidden = true }
                }
            })
        }
    }
}

// MARK: The bar that comes in at the top

struct HoverBar: View {
    @ObservedObject var web: WebModel

    var body: some View {
        ZStack {
            WindowDragArea()
            Text(web.title.isEmpty ? web.site.name : web.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 190)
                .allowsHitTesting(false)
            HStack(spacing: 2) {
                BarButton("chevron.left", "Back") { web.goBack() }
                    .disabled(!web.canGoBack)
                BarButton("chevron.right", "Forward") { web.goForward() }
                    .disabled(!web.canGoForward)
                Spacer()
                BarButton("house", "Home") { web.goHome() }
                BarButton(web.isLoading ? "xmark" : "arrow.clockwise", web.isLoading ? "Stop" : "Reload") {
                    web.isLoading ? web.webView.stopLoading() : web.reload()
                }
                BarButton("link", "Copy Link") { web.copyLink() }
                BarButton("safari", "Open in Browser") { web.openInBrowser() }
                if !web.standalone {
                    BarButton("dock.arrow.up.rectangle", "Make Dock App") { Library.shared.makeApp(for: web.site) }
                }
            }
            .padding(.leading, 78)
            .padding(.trailing, web.standalone ? 8 : 40)
        }
        .frame(height: 28)
        .background(.bar)
    }
}

struct BarButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    init(_ symbol: String, _ help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(hovering && enabled ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .secondary : .quaternary)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A hairline of progress along the very top while a page loads.
struct LoadingLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: proxy.size.width * max(0.08, progress), height: 2)
                .animation(.easeOut(duration: 0.2), value: progress)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }
}
