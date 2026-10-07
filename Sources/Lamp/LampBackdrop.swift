import SwiftUI
import AVFoundation

/// The camera moves only between steps. The held frames also cover loading and Reduce Motion.
struct LampBackdrop: NSViewRepresentable {
    static let page = NSColor(srgbRed: 254.0 / 255, green: 253.0 / 255, blue: 252.0 / 255, alpha: 1)
    let step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> LampFilmView { LampFilmView() }

    func updateNSView(_ view: LampFilmView, context: Context) {
        view.go(to: step, animated: !reduceMotion)
    }

    static func dismantleNSView(_ view: LampFilmView, coordinator: ()) { view.stop() }
}

@MainActor final class LampFilmView: NSView {
    private let player = AVPlayer()
    private let film = AVPlayerLayer()
    private let still = CALayer()
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var readiness: NSKeyValueObservation?
    private var itemStatus: NSKeyValueObservation?
    private var generation = 0
    private var step: Int?
    private var moving = false
    private var prepared = false
    private var holds: [CGImage?] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = LampBackdrop.page.cgColor
        film.player = player
        film.videoGravity = .resizeAspectFill
        film.isHidden = true
        still.contentsGravity = .resizeAspectFill
        still.masksToBounds = true
        layer?.addSublayer(film)
        layer?.addSublayer(still)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        for index in 0..<3 {
            let url = Bundle.main.url(forResource: "step\(index)", withExtension: "png", subdirectory: "Onboarding")
            let image = url.flatMap { NSImage(contentsOf: $0) }
            holds.append(image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        }
        guard let url = Bundle.main.url(forResource: "onboarding", withExtension: "mp4", subdirectory: "Onboarding") else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.didEnd() }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
                                                                 object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish() }
        }
        readiness = film.observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.reveal() }
        }
        itemStatus = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in self?.finish() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        film.frame = bounds
        still.frame = bounds
        CATransaction.commit()
    }

    func go(to next: Int, animated: Bool) {
        let next = min(max(next, 0), 2)
        guard next != step else {
            if !animated && moving { finish() }
            return
        }
        let previous = step
        let interrupted = moving
        generation += 1
        let request = generation
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        prepared = false
        step = next
        // Rapid navigation and restored setup open directly at the requested composition.
        guard animated, !interrupted, let previous, abs(next - previous) == 1,
              let item = player.currentItem, item.status != .failed else {
            finish()
            return
        }
        moving = true
        let startFrame = next > previous ? previous * 48 : (4 - previous) * 48
        item.forwardPlaybackEndTime = CMTime(value: Int64(startFrame + 48), timescale: 30)
        player.seek(to: CMTime(value: Int64(startFrame), timescale: 30), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, finished, self.generation == request, self.moving else { return }
                self.prepared = true
                self.reveal()
            }
        }
    }

    private func reveal() {
        guard moving, prepared, film.isReadyForDisplay else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        film.isHidden = false
        still.isHidden = true
        CATransaction.commit()
        player.play()
    }

    private func finish() {
        player.pause()
        moving = false
        prepared = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        still.contents = holds[step ?? 0]
        still.isHidden = false
        film.isHidden = true
        CATransaction.commit()
    }

    private func didEnd() {
        // An end notification can arrive after navigation has already started a new seek.
        guard moving, prepared, let item = player.currentItem,
              CMTimeCompare(player.currentTime(), item.forwardPlaybackEndTime) >= 0 else { return }
        finish()
    }

    func stop() {
        generation += 1
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
        readiness = nil
        itemStatus = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil
        failureObserver = nil
    }
}
