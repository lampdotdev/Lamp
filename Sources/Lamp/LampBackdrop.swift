import SwiftUI
import AVFoundation

/// Lamp's page: the warm white the welcome and the desk are drawn on.
enum LampBackdrop {
    static let page = NSColor(srgbRed: 254.0 / 255, green: 253.0 / 255, blue: 252.0 / 255, alpha: 1)
}

/// The welcome's film: an app changing while it's used, played over and over without sound. Nothing at all
/// when the film isn't in the bundle, so a build without it still opens on the words alone.
struct WelcomeLoop: NSViewRepresentable {
    static let url = Bundle.main.url(forResource: "welcome-loop", withExtension: "mp4", subdirectory: "Onboarding")

    func makeNSView(context: Context) -> LoopView { LoopView(url: Self.url) }
    func updateNSView(_ view: LoopView, context: Context) {}
    static func dismantleNSView(_ view: LoopView, coordinator: ()) { view.stop() }

    @MainActor final class LoopView: NSView {
        private let player = AVQueuePlayer()
        private let film = AVPlayerLayer()
        private var looper: AVPlayerLooper?

        init(url: URL?) {
            super.init(frame: .zero)
            wantsLayer = true
            film.player = player
            film.videoGravity = .resizeAspect
            layer?.addSublayer(film)
            player.isMuted = true
            guard let url else { return }
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.play()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            film.frame = bounds
            CATransaction.commit()
        }

        func stop() {
            player.pause()
            looper = nil
        }
    }
}
