import SwiftUI

/// A bottle's card as a game-style dialog: it flies in from below the window, tilts into place, and the bottle
/// pops up in front of a slowly turning sunburst. Arrows flip through the shelf without closing it.
struct BottleDialog: View {
    let id: String
    @EnvironmentObject var shelf: Shelf
    @State private var popped = false

    /// The bottles in the order they stand on the shelf.
    private var order: [Bottle] {
        let active = shelf.active.sorted {
            let a = FlavorFamily.allCases.firstIndex(of: $0.flavor) ?? 0, b = FlavorFamily.allCases.firstIndex(of: $1.flavor) ?? 0
            return a == b ? $0.heat < $1.heat : a < b
        }
        return active + shelf.retired
    }

    private func neighbor(_ step: Int) -> Bottle? {
        let all = order
        guard let i = all.firstIndex(where: { $0.id == id }), !all.isEmpty else { return nil }
        return all[(i + step + all.count) % all.count]
    }

    var body: some View {
        if let bottle = shelf.bottle(id) {
            HStack(spacing: 18) {
                arrow("chevron.left", label: "Previous bottle") { flip(-1) }
                card(bottle)
                arrow("chevron.right", label: "Next bottle") { flip(1) }
            }
            .onAppear { pop() }
            .onChange(of: id) { pop() }
        }
    }

    private func card(_ bottle: Bottle) -> some View {
        BottleDetail(id: id, startRetiring: shelf.openRetiring, onDelete: {
            shelf.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { shelf.confirmDeleteID = id }
        })
        .id(id)
        .padding(.leading, 230)
        // The hero panel takes exactly the card's height, whatever the details need.
        .background(alignment: .leading) {
            hero(bottle)
                .frame(width: 230)
                .frame(maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .trailing) { Rectangle().fill(Zine.navy).frame(width: 2.5) }
        }
        .background(Paper.background)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Zine.navy, lineWidth: 2.5))
        // A chunky flat shadow, like a sticker lifted off the page.
        .background(RoundedRectangle(cornerRadius: 18).fill(Zine.navy).offset(x: 7, y: 9))
        .overlay(alignment: .topTrailing) { closeButton.offset(x: 16, y: -16) }
        .environment(\.colorScheme, .light)
    }

    private func hero(_ bottle: Bottle) -> some View {
        ZStack {
            VStack(spacing: 14) {
                Image(nsImage: BottleImages.image(for: bottle))
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 170, maxHeight: 270)
                    .saturation(bottle.isRetired ? 0 : 1)
                    .shadow(color: Zine.navy.opacity(0.35), radius: 0, x: 5, y: 6)
                    .scaleEffect(popped ? 1 : 0.4, anchor: .bottom)
                    .rotationEffect(.degrees(popped ? -4 : -24), anchor: .bottom)
                    .opacity(popped ? 1 : 0)
                if bottle.isRetired {
                    Text("retired")
                        .font(.system(size: 13, weight: .heavy, design: .serif)).kerning(2)
                        .foregroundStyle(Zine.red)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Zine.red, lineWidth: 2))
                        .rotationEffect(.degrees(-8))
                } else {
                    HStack(spacing: 6) {
                        Text("🌶️ \(bottle.intensity)")
                        if let score = bottle.score { Text("★ \(score)").foregroundStyle(Zine.red) }
                    }
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Zine.navy)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(Zine.cream))
                    .overlay(Capsule().strokeBorder(Zine.navy, lineWidth: 2))
                    .scaleEffect(popped ? 1 : 0.3)
                    .opacity(popped ? 1 : 0)
                }
            }
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                (bottle.isRetired ? Color(white: 0.85) : Zine.yellow)
                Sunburst(colors: bottle.isRetired ? [Color(white: 0.78), Color(white: 0.88)] : [Zine.orange.opacity(0.5), Zine.yellow])
                    .frame(width: 700, height: 700)
            }
        }
    }

    private var closeButton: some View {
        Button { shelf.close() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Zine.cream)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Zine.red))
                .overlay(Circle().strokeBorder(Zine.navy, lineWidth: 2.5))
                .background(Circle().fill(Zine.navy).offset(x: 3, y: 4))
        }
        .buttonStyle(PressyButtonStyle())
        .keyboardShortcut(.cancelAction)
        .help("Close")
        .accessibilityLabel("Close")
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(Zine.navy)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Zine.cream))
                .overlay(Circle().strokeBorder(Zine.navy, lineWidth: 2.5))
                .background(Circle().fill(Zine.navy).offset(x: 3, y: 4))
        }
        .buttonStyle(PressyButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    private func flip(_ step: Int) {
        guard let next = neighbor(step) else { return }
        shelf.openRetiring = false
        shelf.openID = next.id
    }

    private func pop() {
        popped = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.12)) { popped = true }
    }
}

/// Rays turning slowly behind the bottle.
struct Sunburst: View {
    let colors: [Color]

    var body: some View {
        TimelineView(.animation) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120) * 3
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let rays = 18
                let radius = max(size.width, size.height)
                for i in 0..<rays {
                    let start = Angle.degrees(Double(i) * 360 / Double(rays))
                    let end = Angle.degrees(Double(i) * 360 / Double(rays) + 360 / Double(rays) / 2)
                    var path = Path()
                    path.move(to: center)
                    path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                    path.closeSubpath()
                    context.fill(path, with: .color(colors[0]))
                }
            }
            .rotationEffect(.degrees(angle))
        }
        .accessibilityHidden(true)
    }
}

/// Squashes a little when pressed, like a game button.
struct PressyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

/// Flies in from below the window with a tilt, and back out the same way.
struct FlyIn: ViewModifier {
    let amount: Double
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(amount * 9))
            .offset(y: amount * 900)
    }
}
