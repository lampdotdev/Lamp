import SwiftUI

/// A wish whose folder a newer Lamp laid out differently (its meta.json's `layout` is above `NewerWish.layout`). This
/// Lamp would read such a folder as an empty draft and write a new app into it on the first message, so it's left
/// alone: never listed among the wishes, built, saved, migrated or written to, only shown on the desk as made by a newer
/// Lamp until this one is updated.
struct NewerWish: Identifiable, Hashable {
    /// How wish folders are laid out in this Lamp. A wish from before meta.json said so is this layout.
    static let layout = 1

    let id: String
    let name: String
    let dir: URL

    private struct Meta: Decodable {
        var name: String?
        var layout: Int?
    }

    /// The wish in this folder, if a newer Lamp laid it out. Read on its own, before anything else of meta.json, since
    /// a newer layout may leave out what this Lamp's reading requires.
    nonisolated static func read(at dir: URL) -> NewerWish? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(".lamp/meta.json")),
              let meta = try? JSONDecoder().decode(Meta.self, from: data),
              let layout = meta.layout, layout > Self.layout else { return nil }
        return NewerWish(id: dir.lastPathComponent, name: meta.name ?? dir.lastPathComponent, dir: dir)
    }

    /// Its icon as Lamp last drew it, at the wish's root or in one of its app folders: only read, never drawn again.
    var icon: NSImage? {
        let fm = FileManager.default
        let folders = [dir] + ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return folders.lazy.compactMap { NSImage(contentsOf: $0.appendingPathComponent(".lamp/icon.png")) }.first
    }
}

/// A newer Lamp's wish on the desk: its icon faded and its name, with what it is under it. A click offers the update
/// that opens it, rather than opening it here.
struct NewerWishIcon: View {
    let wish: NewerWish
    @State private var icon: NSImage?

    static let words = "Made by a newer Lamp"

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    BlueprintIcon(letter: wish.name.first, size: 76)
                }
            }
            .frame(width: 76, height: 76)
            .opacity(0.5)
            VStack(spacing: 2) {
                Text(wish.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                Text(Self.words)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { Updater.shared.checkForUpdates() }
        .help("Update Lamp to open \(wish.name)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(wish.name)
        .accessibilityValue(Self.words)
        .accessibilityHint("Update Lamp to open it")
        .accessibilityAction { Updater.shared.checkForUpdates() }
        .task(id: wish.dir) {
            let wish = wish
            icon = await Task.detached { wish.icon }.value
        }
    }
}
