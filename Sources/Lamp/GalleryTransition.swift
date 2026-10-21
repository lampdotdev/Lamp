import SwiftUI
import AppKit

/// The light on an app being changed, tried in the gallery over made-up windows: a Mac app in the system's look, a
/// dark game and a bright one, the three grounds it has to read on. The layers are the apps' own
/// (`LampTransition.Look`), driven the way `LampTransition` drives them: begin, land, end.
struct TransitionPlayground: View {
    enum Screen: String, CaseIterable, Identifiable {
        case mac = "Mac App", darkGame = "Dark Game", brightGame = "Bright Game", all = "All Three"
        var id: Self { self }
    }

    @AppStorage("galleryTransitionScreen") private var screen = Screen.mac
    @StateObject private var stage = TransitionStage()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Screen", selection: $screen) {
                ForEach(Screen.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Button("Glow") { stage.begin() }.disabled(stage.state != .idle)
                Button("Change Goes In") { stage.land() }.disabled(stage.state == .leaving)
                Button("Let Go") { stage.end() }.disabled(stage.state != .glowing)
                Button("Whole Change") { stage.wholeChange() }.disabled(stage.state != .idle)
                    .help("Glows for three seconds, then the change goes in")
                Spacer()
                Toggle("Reduce Motion", isOn: $stage.still)
            }

            ForEach(screen == .all ? [.mac, .darkGame, .brightGame] : [screen]) { shown in
                MockWindow(screen: shown, stage: stage)
            }
        }
    }
}

/// What the buttons do to every window shown, as `LampTransition` does to the app's windows: a fresh set of layers
/// for each change, which goes once the light has crossed or faded.
@MainActor final class TransitionStage: ObservableObject {
    enum State { case idle, glowing, leaving }

    @Published private(set) var state = State.idle
    /// Bumped once a change's layers are done with, so each window makes fresh ones, as a new `Glass` would be.
    @Published private(set) var generation = 0
    @Published var still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private let looks = NSHashTable<LampTransition.Look>.weakObjects()
    private var pending: DispatchWorkItem?

    func register(_ look: LampTransition.Look) {
        looks.add(look)
        if state == .glowing { look.glow(still: still) }
    }

    func begin() {
        guard state == .idle else { return }
        state = .glowing
        for look in looks.allObjects { look.glow(still: still) }
    }

    /// Like the app, a change that goes in without a begin still shows the light crossing.
    func land() {
        guard state != .leaving else { return }
        pending?.cancel()
        let seconds = looks.allObjects.map { $0.reveal(still: still) }.max() ?? 0
        leave(after: seconds)
    }

    func end() {
        guard state == .glowing else { return }
        pending?.cancel()
        let seconds = looks.allObjects.map { $0.fade() }.max() ?? 0
        leave(after: seconds)
    }

    func wholeChange() {
        begin()
        later(3) { $0.land() }
    }

    private func leave(after seconds: TimeInterval) {
        state = .leaving
        later(seconds) { stage in
            stage.generation += 1
            stage.state = .idle
        }
    }

    private func later(_ seconds: TimeInterval, _ work: @escaping @MainActor (TransitionStage) -> Void) {
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { if let self { work(self) } }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }
}

private struct LookLayer: NSViewRepresentable {
    let stage: TransitionStage
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> LampTransition.Look {
        let look = LampTransition.Look(frame: .zero)
        look.cornerRadius = cornerRadius
        stage.register(look)
        return look
    }

    func updateNSView(_ look: LampTransition.Look, context: Context) {
        look.cornerRadius = cornerRadius
    }
}

/// A made-up window: the screen's content, its traffic lights, its rounding and shadow, and the light over it.
private struct MockWindow: View {
    let screen: TransitionPlayground.Screen
    @ObservedObject var stage: TransitionStage

    private let radius: CGFloat = 16

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch screen {
            case .darkGame: DarkGame()
            case .brightGame: BrightGame()
            default: MacAppScreen()
            }
            TrafficLights().padding(.leading, 14).padding(.top, 14)
            LookLayer(stage: stage, cornerRadius: radius).id(stage.generation)
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .padding(.vertical, 6)
    }
}

private struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) {
                Circle().fill($0).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            }
        }
    }
}

// MARK: The screens

/// A plain Mac app in the system's look, light or dark with the gallery: a sidebar, a toolbar and a list.
private struct MacAppScreen: View {
    private let places = [("tray", "Inbox", 12), ("calendar", "Today", 4), ("star", "Upcoming", 0), ("checkmark.circle", "Done", 0)]
    private let tasks = ["Water the basil", "Call the plumber about the sink", "Pick up the dry cleaning",
                         "Book the dentist", "Send the photos to Sam", "Renew the library books"]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Spacer().frame(height: 40)
                ForEach(Array(places.enumerated()), id: \.offset) { index, place in
                    HStack {
                        Image(systemName: place.0).foregroundStyle(index == 0 ? Color.white : Color.accentColor).frame(width: 18)
                        Text(place.1)
                        Spacer()
                        if place.2 > 0 { Text("\(place.2)").foregroundStyle(index == 0 ? .white.opacity(0.8) : .secondary) }
                    }
                    .font(.callout)
                    .foregroundStyle(index == 0 ? .white : .primary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(index == 0 ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(width: 170)
            .background(.regularMaterial)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Inbox").font(.headline)
                    Spacer()
                    Image(systemName: "plus")
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .frame(height: 44)
                Divider()
                ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                    HStack(spacing: 10) {
                        Image(systemName: index == 2 ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(index == 2 ? Color.accentColor : .secondary)
                        Text(task).strikethrough(index == 2).foregroundStyle(index == 2 ? .secondary : .primary)
                        Spacer()
                    }
                    .font(.body)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(index == 1 ? Color.accentColor.opacity(0.15) : .clear)
                    Divider().padding(.leading, 42)
                }
                Spacer()
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

/// A game at night: deep space, stars, a ship and its score, all of it dark.
private struct DarkGame: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.02, blue: 0.08), Color(red: 0.08, green: 0.03, blue: 0.16)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                var seed: UInt64 = 7
                func next() -> CGFloat {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
                }
                for _ in 0..<140 {
                    let point = CGPoint(x: next() * size.width, y: next() * size.height)
                    let r = 0.4 + next() * 1.4
                    context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: r, height: r)), with: .color(.white.opacity(0.3 + next() * 0.7)))
                }
                // A planet low on the right, and the ship.
                let planet = CGRect(x: size.width * 0.68, y: size.height * 0.55, width: size.width * 0.4, height: size.width * 0.4)
                context.fill(Path(ellipseIn: planet), with: .linearGradient(Gradient(colors: [Color(red: 0.35, green: 0.2, blue: 0.55), Color(red: 0.08, green: 0.04, blue: 0.15)]),
                                                                              startPoint: CGPoint(x: planet.minX, y: planet.minY), endPoint: CGPoint(x: planet.maxX, y: planet.maxY)))
                var ship = Path()
                let c = CGPoint(x: size.width * 0.3, y: size.height * 0.6)
                ship.move(to: CGPoint(x: c.x + 26, y: c.y))
                ship.addLine(to: CGPoint(x: c.x - 16, y: c.y - 14))
                ship.addLine(to: CGPoint(x: c.x - 8, y: c.y))
                ship.addLine(to: CGPoint(x: c.x - 16, y: c.y + 14))
                ship.closeSubpath()
                context.fill(ship, with: .color(Color(red: 0.4, green: 0.95, blue: 1)))
                context.fill(Path(ellipseIn: CGRect(x: c.x - 26, y: c.y - 4, width: 14, height: 8)), with: .color(.orange))
            }
            VStack {
                HStack {
                    Spacer()
                    Text("SCORE 04210").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<3) { _ in Image(systemName: "heart.fill").foregroundStyle(.pink) }
                    Spacer()
                }
            }
            .padding(16)
        }
    }
}

/// A game by day: sky, sun, green hills, clouds and coins, all of it bright.
private struct BrightGame: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.45, green: 0.78, blue: 1), Color(red: 0.85, green: 0.95, blue: 1)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                let w = size.width, h = size.height
                context.fill(Path(ellipseIn: CGRect(x: w * 0.78, y: h * 0.1, width: w * 0.12, height: w * 0.12)), with: .color(Color(red: 1, green: 0.88, blue: 0.3)))
                for (x, y, s) in [(0.15, 0.18, 1.0), (0.5, 0.12, 0.8), (0.62, 0.3, 0.6)] {
                    for (dx, dy, r) in [(0.0, 0.0, 0.05), (0.04, -0.02, 0.06), (0.09, 0.0, 0.045)] {
                        let rr = r * s * w
                        context.fill(Path(ellipseIn: CGRect(x: (x + dx * s) * w, y: (y + dy * s) * h, width: rr * 2, height: rr * 1.4)), with: .color(.white))
                    }
                }
                var far = Path()
                far.move(to: CGPoint(x: 0, y: h * 0.7))
                far.addCurve(to: CGPoint(x: w, y: h * 0.62), control1: CGPoint(x: w * 0.3, y: h * 0.45), control2: CGPoint(x: w * 0.7, y: h * 0.8))
                far.addLine(to: CGPoint(x: w, y: h)); far.addLine(to: CGPoint(x: 0, y: h)); far.closeSubpath()
                context.fill(far, with: .color(Color(red: 0.55, green: 0.85, blue: 0.4)))
                var near = Path()
                near.move(to: CGPoint(x: 0, y: h * 0.82))
                near.addCurve(to: CGPoint(x: w, y: h * 0.8), control1: CGPoint(x: w * 0.4, y: h * 0.7), control2: CGPoint(x: w * 0.6, y: h * 0.95))
                near.addLine(to: CGPoint(x: w, y: h)); near.addLine(to: CGPoint(x: 0, y: h)); near.closeSubpath()
                context.fill(near, with: .color(Color(red: 0.3, green: 0.72, blue: 0.3)))
                for i in 0..<5 {
                    let coin = CGRect(x: w * (0.3 + Double(i) * 0.08), y: h * 0.5, width: 18, height: 18)
                    context.fill(Path(ellipseIn: coin), with: .color(Color(red: 1, green: 0.8, blue: 0.1)))
                    context.stroke(Path(ellipseIn: coin.insetBy(dx: 3, dy: 3)), with: .color(Color(red: 0.9, green: 0.6, blue: 0)), lineWidth: 1.5)
                }
                context.fill(Path(roundedRect: CGRect(x: w * 0.16, y: h * 0.68, width: 28, height: 34), cornerRadius: 6), with: .color(Color(red: 0.95, green: 0.3, blue: 0.3)))
            }
            VStack {
                HStack {
                    Spacer()
                    Label("12", systemImage: "circle.fill").font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.8), in: Capsule())
                }
                Spacer()
            }
            .padding(14)
        }
    }
}
