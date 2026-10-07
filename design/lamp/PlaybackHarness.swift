import AppKit
import AVFoundation

/// An isolated preview that never opens Lamp's store or the user's generated apps.
@main @MainActor final class PlaybackHarness: NSObject, NSApplicationDelegate {
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    private let film = LampFilmView(frame: NSRect(x: 0, y: 0, width: 1080, height: 760))
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private var motionObserver: NSObjectProtocol?
    private var step = 0
    private static var retained: PlaybackHarness?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let harness = PlaybackHarness()
        retained = harness
        app.delegate = harness
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Onboarding Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        menu.addItem(item)
        app.mainMenu = menu
        harness.show()
        if CommandLine.arguments.contains("--verify") {
            Task { await harness.verify() }
        }
        app.run()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func show() {
        window.title = "Lamp — Onboarding Film Preview"
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 900, height: 660)
        let root = NSView(frame: film.frame)
        film.autoresizingMask = [.width, .height]
        root.addSubview(film)
        window.contentView = root
        titleLabel.font = .systemFont(ofSize: 42, weight: .bold)
        titleLabel.alignment = .center
        subtitle.font = .systemFont(ofSize: 20)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        let back = NSButton(title: "Back", target: self, action: #selector(previous))
        let next = NSButton(title: "Continue", target: self, action: #selector(nextStep))
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.update() }
        }
        for view in [titleLabel, subtitle, back, next] {
            root.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: film.topAnchor, constant: 110),
            titleLabel.centerXAnchor.constraint(equalTo: film.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            subtitle.centerXAnchor.constraint(equalTo: film.centerXAnchor),
            back.leadingAnchor.constraint(equalTo: film.leadingAnchor, constant: 30),
            back.bottomAnchor.constraint(equalTo: film.bottomAnchor, constant: -25),
            next.trailingAnchor.constraint(equalTo: film.trailingAnchor, constant: -30),
            next.bottomAnchor.constraint(equalTo: film.bottomAnchor, constant: -25),
        ])
        update()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func previous() { step = max(0, step - 1); update() }
    @objc private func nextStep() { step = min(2, step + 1); update() }

    private func update() {
        titleLabel.stringValue = ["What do you wish you had?", "What should your first app do?", "Get Lamp ready"][step]
        subtitle.stringValue = ["Lamp turns your ideas into your very own Mac apps.", "Describe an idea. Make it yours.", "Two things to set up, then you can start."][step]
        film.go(to: step, animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func verify() async {
        func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        func check(_ condition: Bool, _ message: String) {
            guard condition else { print("FAIL: \(message)"); exit(1) }
            print("PASS: \(message)")
        }
        let layers = film.layer!.sublayers!
        let video = layers.compactMap { $0 as? AVPlayerLayer }.first!
        let poster = layers[1]
        await wait(0.5)
        check(poster.contents != nil && !poster.isHidden, "initial hold is visible")
        for next in [1, 2, 1, 0] {
            film.go(to: next, animated: true)
            await wait(0.7)
            check(video.player!.rate > 0 && !video.isHidden && poster.isHidden, "transition to \(next) plays")
            await wait(1.7)
            check(video.player!.rate == 0 && !poster.isHidden && video.isHidden, "step \(next) holds without playback")
        }
        film.go(to: 1, animated: true)
        await wait(0.2)
        film.go(to: 2, animated: true)
        await wait(0.3)
        check(video.player!.rate == 0 && !poster.isHidden, "rapid navigation settles immediately")
        film.go(to: 0, animated: false)
        check(video.player!.rate == 0 && !poster.isHidden, "Reduce Motion skips movement")
        film.go(to: 1, animated: true)
        await wait(0.3)
        film.go(to: 1, animated: false)
        check(video.player!.rate == 0 && !poster.isHidden, "enabling Reduce Motion stops an active move")
        window.setContentSize(NSSize(width: 900, height: 660))
        film.layoutSubtreeIfNeeded()
        check(video.frame == film.bounds && poster.frame == film.bounds, "video and stills resize together")
        let restored = LampFilmView(frame: .zero)
        restored.go(to: 2, animated: true)
        let restoredLayers = restored.layer!.sublayers!
        check(restoredLayers[1].contents != nil && !restoredLayers[1].isHidden,
              "restored setup opens on its still without a transition")
        restored.stop()
        film.stop()
        check(video.player!.currentItem == nil, "dismantling releases the movie")
        print("All onboarding playback checks passed")
        NSApp.terminate(nil)
    }
}
