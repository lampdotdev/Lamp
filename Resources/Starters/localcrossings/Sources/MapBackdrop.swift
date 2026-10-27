import SwiftUI
import MapKit

/// The map of the place the paper was made for, about three kilometers across, in gray, behind everything: so
/// the first look says this puzzle is about here. It's a still picture of Apple's map, made once for each
/// place, size and appearance and kept on disk, so after the first time it's there as the window opens.
struct MapBackdrop: View {
    let latitude: Double
    let longitude: Double

    @Environment(\.colorScheme) private var scheme
    @State private var picture: NSImage?

    var body: some View {
        GeometryReader { geometry in
            let key = Key(latitude: latitude, longitude: longitude, dark: scheme == .dark, size: Self.bucket(geometry.size))
            ZStack {
                if let shown = picture ?? Self.kept(key) {
                    Image(nsImage: shown)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .grayscale(1)
                        .transition(.opacity)
                }
            }
            .task(id: key) {
                if let kept = Self.kept(key) {
                    picture = kept
                    return
                }
                let made = await Self.picture(for: key)
                withAnimation(.easeOut(duration: 0.6)) { picture = made }
            }
        }
        .accessibilityHidden(true)
    }

    private struct Key: Hashable {
        var latitude: Double
        var longitude: Double
        var dark: Bool
        var size: CGSize

        var file: String {
            String(format: "%.4f,%.4f,%@,%.0fx%.0f.png", latitude, longitude, dark ? "dark" : "light", size.width, size.height)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(latitude)
            hasher.combine(longitude)
            hasher.combine(dark)
            hasher.combine(size.width)
            hasher.combine(size.height)
        }
    }

    @MainActor private static var made: [Key: NSImage] = [:]
    private static let folder = LampStore.folder.appendingPathComponent("Maps", isDirectory: true)

    /// The picture already made for this place, size and appearance, from memory or from disk.
    @MainActor private static func kept(_ key: Key) -> NSImage? {
        if let image = made[key] { return image }
        guard let image = NSImage(contentsOf: folder.appendingPathComponent(key.file)) else { return nil }
        made[key] = image
        return image
    }

    /// Sizes rounded up to the next 400 points, so resizing the window makes a new picture only now and then.
    private static func bucket(_ size: CGSize) -> CGSize {
        CGSize(width: min(2_400, (size.width / 400).rounded(.up) * 400), height: min(2_000, (size.height / 400).rounded(.up) * 400))
    }

    @MainActor private static func picture(for key: Key) async -> NSImage? {
        if let kept = made[key] { return kept }
        guard key.size.width > 0, key.size.height > 0 else { return nil }
        let options = MKMapSnapshotter.Options()
        let across = 3_200.0
        options.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: key.latitude, longitude: key.longitude),
                                            latitudinalMeters: across * key.size.height / key.size.width,
                                            longitudinalMeters: across)
        options.size = key.size
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        options.appearance = NSAppearance(named: key.dark ? .darkAqua : .aqua)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        made[key] = snapshot.image
        // Only the last few places are kept: a map is a few hundred kilobytes.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let tiff = snapshot.image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: folder.appendingPathComponent(key.file), options: .atomic)
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let byAge = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for old in byAge.dropFirst(12) { try? FileManager.default.removeItem(at: old) }
        return snapshot.image
    }
}
