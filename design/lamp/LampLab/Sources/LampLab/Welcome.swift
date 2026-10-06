import SwiftUI

let ideas: [(String, String, Double)] = [
    ("Downloads Tidy", "folder.badge.gearshape", 0.58), ("Screenshot Notes", "camera.viewfinder", 0.75),
    ("Clipboard Shelf", "list.clipboard", 0.08), ("Reading Queue", "books.vertical", 0.33),
    ("Focus Timer", "timer", 0.0), ("Photo Studio", "photo.on.rectangle.angled", 0.9),
    ("Receipt Box", "doc.text.magnifyingglass", 0.38), ("Meeting Recap", "person.2.wave.2", 0.62),
    ("Habit Garden", "leaf", 0.3), ("Recipe Keeper", "fork.knife", 0.05), ("Plant Care", "drop", 0.45),
    ("Trip Planner", "airplane", 0.55), ("Subscriptions", "creditcard", 0.7),
    ("Word of the Day", "character.book.closed", 0.12), ("Gift Ideas", "gift", 0.95),
    ("Invoice Maker", "doc.richtext", 0.6), ("Mood Journal", "face.smiling", 0.15),
    ("Workout Log", "figure.run", 0.02), ("Flashcards", "rectangle.on.rectangle.angled", 0.78),
    ("Tab Sweeper", "safari", 0.57), ("Color Picker", "eyedropper", 0.85), ("Bill Splitter", "divide.circle", 0.35),
]

enum Brand {
    static let ground = Color(red: 0.992, green: 0.984, blue: 0.968)
    static let ink = Color(red: 0.11, green: 0.10, blue: 0.09)
    static let gold = Color(red: 0.91, green: 0.71, blue: 0.29)
    static let brass = Color(red: 0.62, green: 0.45, blue: 0.13)
    static let smoke = Color(red: 0.6, green: 0.5, blue: 0.93)
    static let mist = Color(red: 0.8, green: 0.85, blue: 1.0)
}

struct IdeaIcon: View {
    let symbol: String
    let hue: Double
    var size: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 1),
                                               Color(hue: hue, saturation: 0.75, brightness: 0.88)],
                                      startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(.white.opacity(0.35), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hue: hue, saturation: 0.7, brightness: 0.7).opacity(0.25), radius: size * 0.16, y: size * 0.08)
    }
}

struct Welcome: View {
    static let size = CGSize(width: 1080, height: 760)
    static let stage = CGSize(width: 1080, height: 400)

    let picture: CGImage
    let labels: [Label]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("What do you wish you had?")
                .font(.system(size: 54, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(Brand.ink)
            Text("Lamp turns your ideas into your very own Mac apps.")
                .font(.system(size: 19))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            Stage(picture: picture, labels: labels)
                .frame(width: Self.stage.width, height: Self.stage.height)
                .padding(.top, 8)
            Text("Get Started")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 30).frame(height: 40)
                .background(LinearGradient(colors: [Color(red: 0.78, green: 0.58, blue: 0.2), Brand.brass],
                                           startPoint: .top, endPoint: .bottom), in: Capsule())
                .shadow(color: Brand.brass.opacity(0.3), radius: 10, y: 4)
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Brand.ground)
        .environment(\.colorScheme, .light)
    }
}

/// The 3D picture, a warm glow and shadow under it, and the apps' names written over it.
struct Stage: View {
    let picture: CGImage
    let labels: [Label]

    var body: some View {
        let w = Welcome.stage.width, h = Welcome.stage.height
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Image(decorative: picture, scale: 2)
                ForEach(labels.indices, id: \.self) { i in
                    let l = labels[i]
                    Text(l.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .scaleEffect(l.scale)
                        .opacity(l.opacity)
                        .position(x: l.point.x, y: l.point.y + 7)
                }
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                                         .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .frame(width: w, height: h)
    }
}
