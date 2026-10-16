import SwiftUI

/// One item as it stands on the shelf: its spine, or its cover when it faces out. Something lent out leaves
/// a faint outline where it stood; something being read has a ribbon hanging out of the top.
struct StandingItem: View {
    let item: ShelfItem
    let cover: NSImage?

    var body: some View {
        Group {
            if item.facesOut {
                CoverView(item: item, cover: cover)
                    .frame(width: (item.look.height * 0.68).rounded(), height: item.look.height)
            } else {
                Spine(item: item)
                    .frame(width: item.look.width, height: item.look.height)
            }
        }
        .opacity(item.status == .lent ? 0.35 : 1)
        .overlay {
            if item.status == .lent {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.primary.opacity(0.45))
            }
        }
        .overlay(alignment: .top) {
            if item.status == .reading {
                Ribbon().offset(x: item.facesOut ? 20 : 0, y: -10)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 1.5, x: 1, y: 0)
    }
}

struct Spine: View {
    let item: ShelfItem

    var body: some View {
        let look = item.look
        // Darker at the edges and lighter in the middle, as a rounded spine catches the light. The words are
        // overlays, so their length never widens the spine.
        RoundedRectangle(cornerRadius: 2)
            .fill(look.color)
            .overlay(
                LinearGradient(stops: [.init(color: .black.opacity(0.28), location: 0),
                                       .init(color: .white.opacity(0.12), location: 0.35),
                                       .init(color: .clear, location: 0.6),
                                       .init(color: .black.opacity(0.3), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 2)))
            .overlay {
                VStack {
                    Band(color: look.ink)
                    Spacer()
                    Band(color: look.ink)
                }
                .padding(.vertical, 8)
            }
            .overlay {
                // Read top to bottom, as English spines are.
                // The surname too when there's room, else the title alone, made a little smaller if need be.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        title
                        Spacer(minLength: 0)
                        Text(item.creator.split(separator: " ").last.map(String.init) ?? "")
                            .font(.system(size: min(9, look.width * 0.32), design: .serif))
                            .opacity(0.8)
                    }
                    title.minimumScaleFactor(0.75)
                }
                .lineLimit(1)
                .foregroundStyle(look.ink)
                .frame(width: look.height - 34)
                .fixedSize()
                .rotationEffect(.degrees(90))
            }
        .accessibilityElement(children: .ignore)
    }

    private var title: some View {
        Text(item.title)
            .font(.system(size: min(12, item.look.width * 0.42), weight: .semibold, design: .serif))
    }
}

private struct Band: View {
    let color: Color
    var body: some View {
        Rectangle().fill(color.opacity(0.45)).frame(height: 1.5).padding(.horizontal, 3)
    }
}

private struct Ribbon: View {
    var body: some View {
        Path { path in
            path.addLines([.zero, CGPoint(x: 6, y: 0), CGPoint(x: 6, y: 18), CGPoint(x: 3, y: 15), CGPoint(x: 0, y: 18)])
        }
        .fill(Color.red.opacity(0.85))
        .frame(width: 6, height: 18)
    }
}

/// The cover: the real one when it has arrived, otherwise one drawn in the item's colour.
struct CoverView: View {
    let item: ShelfItem
    let cover: NSImage?

    var body: some View {
        if let cover {
            // Filled into whatever size it's given and cut to it, whatever the cover's own proportions.
            Color.clear
                .overlay { Image(nsImage: cover).resizable().scaledToFill() }
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .accessibilityLabel("Cover of \(item.title)")
        } else {
            DrawnCover(item: item)
        }
    }
}

struct DrawnCover: View {
    let item: ShelfItem

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                LinearGradient(colors: [item.look.color, item.look.color.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle()
                    .strokeBorder(item.look.ink.opacity(0.4), lineWidth: 1)
                    .padding(size * 0.06)
                VStack(spacing: size * 0.05) {
                    Text(item.title)
                        .font(.system(size: size * 0.12, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                    Rectangle().fill(item.look.ink.opacity(0.5)).frame(width: size * 0.25, height: 1)
                    Text(item.creator)
                        .font(.system(size: size * 0.075, design: .serif))
                        .italic()
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(item.look.ink)
                .padding(size * 0.14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .accessibilityLabel("Cover of \(item.title)")
    }
}
