import SwiftUI

/// One bottle standing on a plank: its real label (or a painted bottle until one's found), and the heat band on its cap.
struct BottleView: View {
    let bottle: Bottle
    var height: CGFloat = 150

    @EnvironmentObject var shelf: Shelf
    @ObservedObject private var labels = LabelFinder.shared
    @State private var hovering = false

    private var image: NSImage { BottleImages.image(for: bottle) }
    private var style: BottleStyle? { BottleImages.style(for: bottle) }
    /// Jars stand shorter than bottles.
    private var h: CGFloat { height * (style?.scale ?? 1) }
    private var width: CGFloat {
        let size = image.size
        guard size.height > 0 else { return h * 0.3 }
        return min(h * 1.0, max(h * 0.22, h * size.width / size.height))
    }
    private var isLifted: Bool { shelf.lifted == bottle.id }

    var body: some View {
        picture
            .frame(width: width, height: h)
            .overlay {
                if labels.working == bottle.id {
                    ProgressView().controlSize(.small)
                        .padding(6).background(.ultraThinMaterial, in: Circle())
                }
            }
            .frame(height: height, alignment: .bottom)
            .background(alignment: .bottom) {
                // Where it touches the shelf.
                Ellipse().fill(.black.opacity((isLifted ? 0.18 : 0.6) * Look.current.contrast))
                    .frame(width: width * 1.08, height: 7).blur(radius: 2.5)
                    .offset(y: isLifted ? 44 : 3)
            }
            .background {
                if isLifted {
                    Ellipse().fill(Look.current.accent.opacity(0.45)).blur(radius: 22)
                        .frame(width: width * 1.7, height: h * 0.9)
                }
            }
            .brightness(isLifted ? 0.06 : 0)
            .scaleEffect(isLifted ? 1.14 : (hovering ? 1.04 : 1), anchor: .bottom)
            .opacity(shelf.openID == bottle.id ? 0.25 : 1)
            .offset(y: isLifted ? -40 : 0)
            .zIndex(isLifted ? 10 : 0)
            .contentShape(Rectangle())
            .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
            .onTapGesture { shelf.open(bottle.id) }
            .contextMenu {
                Button("Details…") { shelf.open(bottle.id) }
                Button("Find the Real Label") { labels.find(bottle.id, force: true) }
                if bottle.isRetired {
                    Button("Back on the Shelf") { shelf.unretire(bottle.id) }
                } else {
                    Button("Finished It…") {
                        shelf.open(bottle.id, retiring: true)
                    }
                }
            }
            .help(bottle.isRetired ? "\(bottle.name): \(bottle.verdict ?? "retired")" : "\(bottle.name) · \(bottle.intensity)/10 peppers" + (bottle.score.map { " · \($0)/10 stars" } ?? ""))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(bottle.name)
            .accessibilityValue(bottle.isRetired ? "Retired. \(bottle.verdict ?? "")" : "\(bottle.intensity) of 10 peppers" + (bottle.score.map { ", \($0) of 10 stars" } ?? ", not rated"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { shelf.open(bottle.id) }
    }

    @ViewBuilder private var picture: some View {
        let base = Image(nsImage: image).resizable().interpolation(.high)
        ZStack(alignment: .top) {
            if bottle.isRetired {
                base.saturation(0).brightness(-0.15).opacity(0.55)
            } else {
                base.overlay { StudioLight(shape: base) }
            }
            if style != nil { genericLabel }
            if !bottle.hasPhoto { capBand }
        }
        .background {
            // Its shadow on the wall behind, thrown away from the light.
            base.renderingMode(.template)
                .foregroundStyle(.black)
                .opacity((bottle.isRetired ? 0.2 : 0.42) * Look.current.contrast)
                .blur(radius: 6)
                .offset(x: h * 0.1, y: -h * 0.02)
                .opacity(isLifted ? 0 : 1)
        }
    }

    private var genericLabel: some View {
        let top = style?.labelTop ?? 0.49, bottom = style?.labelBottom ?? 0.83
        return Text(bottle.name)
            .font(Look.current.label(max(7, width * 0.11), weight: .heavy))
            .foregroundStyle(.black.opacity(0.75))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.5)
            .lineLimit(4)
            .frame(width: width * 0.8, height: h * (bottom - top) * 0.88)
            .offset(y: h * (top + (bottom - top) * 0.06))
            .opacity(bottle.isRetired ? 0.5 : 1)
    }

    private var capBand: some View {
        let cap = BottleImages.cap(for: bottle)
        return Capsule()
            .fill(bottle.isRetired ? Color.gray : heatColor(bottle.heat))
            .frame(width: max(6, width * (cap.x1 - cap.x0) * 1.04), height: max(2.5, h * 0.022))
            .shadow(color: heatColor(bottle.heat).opacity(bottle.isRetired ? 0 : 0.6), radius: 3)
            .position(x: width * (cap.x0 + cap.x1) / 2, y: h * cap.y)
    }
}

/// Heat as a row of up to ten peppers, and liking as up to ten stars.
struct PepperRow: View {
    let value: Int
    var size: CGFloat = 13
    var onSet: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...10, id: \.self) { n in
                Text("🌶️")
                    .font(.system(size: size))
                    .saturation(n <= value ? 1 : 0)
                    .opacity(n <= value ? 1 : 0.22)
                    .onTapGesture { onSet?(n) }
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heat")
        .accessibilityValue("\(value) of 10 peppers")
        .accessibilityAdjustableAction { d in onSet?(min(10, max(1, value + (d == .increment ? 1 : -1)))) }
    }
}

struct StarRow: View {
    let value: Int?
    var size: CGFloat = 13
    var onSet: ((Int?) -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...10, id: \.self) { n in
                Image(systemName: n <= (value ?? 0) ? "star.fill" : "star")
                    .font(.system(size: size * 0.9))
                    .foregroundStyle(n <= (value ?? 0) ? Color.orange : Color.secondary.opacity(0.6))
                    .contentShape(Rectangle())
                    .onTapGesture { onSet?(value == n ? nil : n) }
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stars")
        .accessibilityValue(value.map { "\($0) of 10 stars" } ?? "Not rated")
        .accessibilityAdjustableAction { d in onSet?(min(10, max(1, (value ?? 0) + (d == .increment ? 1 : -1)))) }
    }
}

/// An outline where a bottle could be, on an empty shelf: a faint shape cut out of the light.
struct GhostBottle: View {
    let line: String
    var height: CGFloat = 150

    var body: some View {
        let image = BottleImages.generic
        let width = height * image.size.width / max(1, image.size.height)
        let shape = Image(nsImage: image).resizable().renderingMode(.template)
        shape
            .foregroundStyle(.black.opacity(0.16))
            .frame(width: width, height: height)
            .background {
                // A rim of light around it, a hair bigger.
                shape.foregroundStyle(Look.current.ink.opacity(0.22))
                    .frame(width: width + 2.5, height: height + 2.5)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line)
            .help(line)
    }
}

/// The one light on the set, laid over anything standing in it: a bright stripe down the side facing the light,
/// a soft roll into shade on the far side, and the top a touch brighter than the base. Masked to the thing's own
/// shape, so a bottle, a jar or a wine bottle is lit the same way.
struct StudioLight<S: View>: View {
    let shape: S

    var body: some View {
        let k = Look.current.contrast
        ZStack {
            LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.06),
                                   .init(color: .white.opacity(0.42 * k), location: 0.2),
                                   .init(color: .white.opacity(0), location: 0.34)],
                           startPoint: .leading, endPoint: .trailing)
                .blendMode(.plusLighter)
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.42),
                                   .init(color: .black.opacity(0.32 * k), location: 0.92),
                                   .init(color: .black.opacity(0.42 * k), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.white.opacity(0.08 * k), .clear, .black.opacity(0.22 * k)],
                           startPoint: .top, endPoint: .bottom)
        }
        .mask(shape)
        .allowsHitTesting(false)
    }
}
