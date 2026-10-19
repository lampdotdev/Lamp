import AppKit
import SwiftUI

/// Redraws each bottle once as a hand-drawn illustration of its real label, so the whole shelf shares one look.
/// The photo stays as the source; the drawing is what stands on the shelf. New bottles join the queue by themselves.
@MainActor
final class Illustrator: ObservableObject {
    static let shared = Illustrator()

    @Published private(set) var working: Set<String> = []
    @Published private(set) var remaining = 0
    private var queue: [String] = []
    private var running = 0
    /// Two at a time: drawings take a while, and the shelf fills in faster this way.
    private let lanes = 2

    /// Bump when the style changes, and every bottle is drawn again in the new one.
    static let version = 2

    static let style = """
        a bold flat illustration, NOT a photo: drawn by hand with gouache paint and crayon, flat areas of saturated \
        red, orange and yellow with chunky visible brush strokes and grainy crayon texture, no photographic shading or \
        reflections, simplified shapes, the label redrawn loosely with wobbly hand-lettered versions of the real brand \
        name and a simplified doodle of its logo, a few thick white highlight strokes on the glass, a slightly uneven \
        thin navy pencil outline, and a white sticker border around the whole bottle. Naive, playful and warm, like a \
        risograph print by a food illustrator
        """

    /// Bottles whose drawing failed this time round, so they aren't retried until the next launch.
    private var failed: Set<String> = []

    private func isWaiting(_ b: Bottle) -> Bool {
        (b.artName == nil || b.artStyle != Self.version) && !failed.contains(b.id) && (b.hasPhoto || b.labelTried == true)
            && LabelFinder.shared.working != b.id && !working.contains(b.id)
    }

    func illustrateMissing() {
        // Bottles on the shelf first, the retired ones after.
        for b in Shelf.shared.bottles.sorted(by: { !$0.isRetired && $1.isRetired }) where isWaiting(b) && !queue.contains(b.id) {
            queue.append(b.id)
        }
        pump()
    }

    /// Draw this one again, from whatever picture it has now.
    func redraw(_ id: String) {
        guard var b = Shelf.shared.bottle(id) else { return }
        b.artTried = nil
        failed.remove(id)
        Shelf.shared.update(b)
        queue.removeAll { $0 == id }
        queue.insert(id, at: 0)
        pump()
    }

    private func pump() {
        remaining = queue.count + working.count
        while running < lanes, !queue.isEmpty {
            let id = queue.removeFirst()
            running += 1
            working.insert(id)
            Task {
                await draw(id)
                working.remove(id)
                running -= 1
                pump()
            }
        }
    }

    private func draw(_ id: String) async {
        guard let bottle = Shelf.shared.bottle(id) else { return }
        let subject = "\(bottle.maker) \(bottle.name)".trimmingCharacters(in: .whitespaces)
        let backdrop = "Keep the bottle's real shape, colors, cap and label layout so it's instantly recognizable. " +
            "One bottle, upright, whole, centered, on a plain flat light pink background with nothing else."
        var drawing: NSImage?
        do {
            if bottle.hasPhoto {
                let photo = BottleImages.photo(for: bottle)
                drawing = try await LampAI.editImage(photo, "Reimagine this bottle of \(subject) hot sauce as \(Self.style). " + backdrop,
                                                     aspectRatio: "3:4")
            } else {
                drawing = try await LampAI.makeImage("A bottle of \(subject) hot sauce drawn as \(Self.style). " + backdrop,
                                                     aspectRatio: "3:4")
            }
        } catch {
            fputs("Couldn't draw \(bottle.name): \(error.localizedDescription)\n", stderr)
        }
        guard var b = Shelf.shared.bottle(id) else { return }
        b.artTried = true
        if let drawing, let cut = await Cutout.make(drawing), let name = BottleImages.save(cut) {
            if let old = b.artName { BottleImages.remove(old) }
            b.artName = name
            b.artStyle = Self.version
            withAnimation(.easeInOut(duration: 0.6)) { Shelf.shared.update(b) }
        } else {
            fputs("Drawing for \(b.name) couldn't be cut out\n", stderr)
            failed.insert(id)
            Shelf.shared.update(b)
        }
    }
}
