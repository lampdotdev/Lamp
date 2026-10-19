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
                Ellipse().fill(Zine.navy.opacity(isLifted ? 0.12 : 0.25)).frame(width: width * 1.1, height: 6).blur(radius: 2)
                    .offset(y: isLifted ? 44 : 3)
            }
            .background {
                if isLifted {
                    Ellipse().fill(Zine.yellow.opacity(0.7)).blur(radius: 16)
                        .frame(width: width * 1.6, height: h * 0.9)
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
                base.saturation(0).brightness(-0.1).opacity(0.6)
            } else {
                base
            }
            if style != nil { genericLabel }
            if !bottle.hasPhoto { capBand }
        }
    }

    private var genericLabel: some View {
        let top = style?.labelTop ?? 0.49, bottom = style?.labelBottom ?? 0.83
        return Text(bottle.name)
            .font(Hand.font(max(9, width * 0.17)))
            .foregroundStyle(Zine.navy)
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

/// An outline where a bottle could be: a gap in the collection.
struct GhostBottle: View {
    let gap: Gap
    var height: CGFloat = 150

    var body: some View {
        let image = BottleImages.generic
        let width = height * image.size.width / max(1, image.size.height)
        Image(nsImage: image).resizable().renderingMode(.template)
            .foregroundStyle(Zine.cream.opacity(0.45))
            .frame(width: width, height: height)
            .background {
                // A faint rim: the same silhouette a hair bigger, a touch brighter.
                Image(nsImage: image).resizable().renderingMode(.template)
                    .foregroundStyle(Zine.navy.opacity(0.35))
                    .frame(width: width + 3, height: height + 3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gap: \(gap.line)")
            .help("A gap on your shelf: \(gap.line)")
    }
}

/// A paper tag hanging off the shelf edge on a string.
struct HangingTag: View {
    let text: String?
    let seed: String
    var faded = false
    var ghost = false
    var peppers: Int? = nil
    var stars: Int? = nil

    private var tilt: Double {
        let n = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 1000 }
        return Double(n % 9) - 4
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Zine.navy.opacity(ghost ? 0.35 : 0.8)).frame(width: 1.2, height: 9)
            VStack(spacing: 3) {
                if let text {
                    Text(text)
                        .font(Hand.font(12.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if peppers != nil || stars != nil {
                    HStack(spacing: 6) {
                        if let peppers {
                            HStack(spacing: 1) { Text("🌶️").font(.system(size: text == nil ? 11 : 9)); Text("\(peppers)") }
                        }
                        if let stars {
                            HStack(spacing: 1) { Image(systemName: "star.fill").font(.system(size: text == nil ? 10 : 8)).foregroundStyle(Zine.orange); Text("\(stars)") }
                        }
                    }
                    .font(.system(size: text == nil ? 12.5 : 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
                }
            }
                .foregroundStyle(Zine.navy.opacity(ghost ? 0.7 : 1))
                .padding(.horizontal, 6).padding(.top, 9).padding(.bottom, 6)
                .frame(minWidth: text == nil ? 70 : 100, maxWidth: 100)
                .background {
                    ZStack(alignment: .top) {
                        if ghost {
                            RoundedRectangle(cornerRadius: 3).strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                                .foregroundStyle(Zine.navy.opacity(0.45))
                        } else {
                            RoundedRectangle(cornerRadius: 3).fill(Zine.pinkShadow).offset(x: 2, y: 3)
                            RoundedRectangle(cornerRadius: 3).fill(Zine.cream)
                            RoundedRectangle(cornerRadius: 3).strokeBorder(Zine.navy, lineWidth: 1.2)
                            Circle().fill(Zine.teal).frame(width: 5, height: 5).padding(.top, 3)
                        }
                    }
                }
                .saturation(faded ? 0 : 1)
                .opacity(faded ? 0.75 : 1)
        }
        .rotationEffect(.degrees(tilt), anchor: .top)
    }
}
