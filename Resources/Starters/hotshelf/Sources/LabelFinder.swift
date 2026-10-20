import AppKit
import SwiftUI

/// Finds the real label for bottles that don't have a photo yet: the product's own photo from Open Food Facts
/// when the AI agrees it's the right bottle, or else a painted likeness of it. Either way it's cut out
/// on this Mac and stood on the shelf. One bottle at a time, gently, so the open database isn't hammered.
@MainActor
final class LabelFinder: ObservableObject {
    static let shared = LabelFinder()

    @Published private(set) var working: String?
    @Published private(set) var remaining = 0
    private var queue: [String] = []
    private var running = false
    private var lastSearch = Date.distantPast

    /// Every bottle still standing as a painted placeholder.
    func findMissing() {
        // Bottles on the shelf first, the retired ones after.
        for b in Shelf.shared.bottles.sorted(by: { !$0.isRetired && $1.isRetired }) where !b.hasPhoto && b.labelTried != true && !queue.contains(b.id) {
            queue.append(b.id)
        }
        start()
    }

    /// One bottle, straight away (for "Find the Real Label").
    func find(_ id: String, force: Bool = false) {
        queue.removeAll { $0 == id }
        queue.insert(id, at: 0)
        start()
    }

    private func start() {
        remaining = queue.count + (working == nil ? 0 : 1)
        guard !running, !queue.isEmpty else { return }
        running = true
        Task {
            while !queue.isEmpty {
                let id = queue.removeFirst()
                working = id
                await findOne(id)
                remaining = queue.count
            }
            working = nil
            remaining = 0
            running = false
        }
    }

    private func findOne(_ id: String) async {
        guard let bottle = Shelf.shared.bottle(id) else { return }
        var cutout: NSImage?
        if let photo = await productPhoto(for: bottle) { cutout = await Cutout.make(photo) }
        if cutout != nil { print("Label for \(bottle.name): the maker's photo") }
        if cutout == nil, let painted = await paintedLikeness(of: bottle) {
            cutout = await Cutout.make(painted)
            print("Label for \(bottle.name): painted likeness")
        }
        guard var b = Shelf.shared.bottle(id) else { return }
        b.labelTried = true
        if let cutout, let name = BottleImages.save(cutout) {
            if b.hasPhoto, let old = b.imageName { BottleImages.remove(old) }
            b.imageName = name
            withAnimation(.easeInOut(duration: 0.5)) { Shelf.shared.update(b) }
        } else {
            Shelf.shared.update(b)
        }
    }

    // MARK: The maker's photo

    private struct Hit { var title: String; var image: URL }

    private func productPhoto(for b: Bottle) async -> NSImage? {
        // Open Food Facts asks for no more than about ten searches a minute.
        let wait = 6.5 - Date().timeIntervalSince(lastSearch)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        lastSearch = Date()
        guard let reply = try? await LampAPI.openfoodfacts.get("https://search.openfoodfacts.org/search", query: [
            "q": "\(b.maker) \(b.name)", "page_size": "10", "fields": "product_name,brands,image_front_url",
        ]), let json = reply.json as? [String: Any], let hits = json["hits"] as? [[String: Any]] else { return nil }
        var seen = Set<String>()
        let candidates: [Hit] = hits.compactMap { hit -> Hit? in
            guard let url = (hit["image_front_url"] as? String).flatMap(URL.init(string:)) else { return nil }
            let brands = (hit["brands"] as? [String])?.joined(separator: ", ") ?? (hit["brands"] as? String ?? "")
            let name = hit["product_name"] as? String ?? ""
            let title = [brands, name].filter { !$0.isEmpty }.joined(separator: " – ")
            // The decision model needs distinct options.
            guard !title.isEmpty, seen.insert(title.lowercased()).inserted else { return nil }
            return Hit(title: title, image: url)
        }
        guard !candidates.isEmpty else { return nil }
        let none = "None of these is that sauce"
        guard let answer = try? await LampAI.choose("Which product is exactly this hot sauce (same maker and same flavor)?",
                                                    from: candidates.map(\.title) + [none],
                                                    about: ["maker": b.maker, "name": b.name, "peppers": b.peppers.joined(separator: ", ")]),
              let choice = answer.choice, choice != none, (answer.confidence ?? 0) > 0.5,
              let hit = candidates.first(where: { $0.title == choice }) else { return nil }
        // The biggest version of the photo, falling back to the one listed.
        let full = URL(string: hit.image.absoluteString.replacingOccurrences(of: ".400.jpg", with: ".full.jpg")) ?? hit.image
        var photo: NSImage?
        for url in [full, hit.image] {
            if let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) { photo = image; break }
        }
        guard let photo else { return nil }
        // People snap these in shops at odd angles: only keep one that clearly shows this bottle's front.
        let check = try? await LampAI.ask(
            "Does this photo clearly show the front label of a bottle or jar of \(b.maker) \(b.name), standing upright? Answer only yes or no.",
            images: [photo])
        guard check?.lowercased().contains("yes") == true else { return nil }
        return photo
    }

    // MARK: A painted likeness

    private func paintedLikeness(of b: Bottle) async -> NSImage? {
        try? await LampAI.makeImage(
            "A product photo of a single bottle of \(b.maker) \(b.name) hot sauce exactly as sold in stores, with its real label, " +
            "cap and bottle shape, standing upright, label facing the camera, the whole bottle in frame, centered on a plain white background, soft studio light.",
            aspectRatio: "3:4")
    }
}
