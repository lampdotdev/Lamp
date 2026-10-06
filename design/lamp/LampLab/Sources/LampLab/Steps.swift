import SwiftUI

/// Close stand-ins for the welcome's three steps, laid over the lamp, to judge the framings with real content.
struct Steps: View {
    let picture: CGImage
    var scale: CGFloat = 2
    /// 0, 1, 2, or in between while moving from one to the next.
    let step: Double

    static let ink = Color(red: 0.11, green: 0.105, blue: 0.1)
    static let page = Color(red: 0.98, green: 0.976, blue: 0.97)

    var body: some View {
        ZStack {
            Image(decorative: picture, scale: scale).interpolation(.high)
            // Behind the later steps' content the lamp fades into the page, so it never competes with it.
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: Self.page.opacity(0.85), location: 0.24),
                                   .init(color: Self.page.opacity(0.85), location: 0.76), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .opacity(min(step, 1))
            Hello().opacity(visibility(0))
            Idea().opacity(visibility(1))
            Setup().opacity(visibility(2))
            Dots(step: step).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 22)
                .opacity(min(step, 1))
        }
        .frame(width: 1080, height: 760)
        .environment(\.colorScheme, .light)
    }

    private func visibility(_ i: Double) -> Double { max(0, 1 - abs(step - i) * 2.2) }
}

private struct Heading: View {
    let title: String
    var detail: String?
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 30, weight: .bold)).tracking(-0.5).foregroundStyle(Steps.ink)
            if let detail { Text(detail).font(.system(size: 15)).foregroundStyle(.secondary) }
        }
    }
}

private struct Primary: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 26).frame(height: 40)
            .background(Steps.ink, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
    }
}

private struct Footer: View {
    let title: String
    var body: some View {
        HStack {
            Text("Back").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            Primary(title: title)
        }
        .padding(.horizontal, 40)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 36)
    }
}

private struct Hello: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("What do you wish you had?")
                .font(.system(size: 54, weight: .bold)).tracking(-1.2).foregroundStyle(Steps.ink)
            Text("Lamp turns your ideas into your very own Mac apps.")
                .font(.system(size: 19)).foregroundStyle(.secondary).padding(.top, 12)
            Primary(title: "Get Started").padding(.top, 30)
            Spacer()
        }
        .padding(.top, 120)
    }
}

private struct Idea: View {
    let tiles = Array(ideas.prefix(6))
    let blurbs = ["Sorts what lands in Downloads, from the menu bar.", "Reads the text in screenshots and makes it searchable.",
                  "Remembers what you copy, one shortcut away.", "Ranks PDFs and links by what matters to your work.",
                  "A menu bar timer with breaks and daily totals.", "Touches up photos with a few words."]
    var body: some View {
        VStack(spacing: 0) {
            Heading(title: "What should your first app do?")
            Text("An app that…").font(.system(size: 17)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                .padding(.horizontal, 20).padding(.vertical, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.black.opacity(0.08)))
                .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
                .padding(.top, 28)
            HStack {
                Text("Need an idea?").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("Show me others").font(.system(size: 13, weight: .medium)).foregroundStyle(Steps.ink)
            }
            .padding(.top, 26)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(tiles.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 12) {
                        IdeaIcon(symbol: tiles[i].1, hue: tiles[i].2, size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tiles[i].0).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Steps.ink)
                            Text(blurbs[i]).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.06)))
                }
            }
            .padding(.top, 10)
            Spacer()
        }
        .frame(width: 720)
        .padding(.top, 90)
        .overlay { Footer(title: "Continue").frame(width: 1080) }
    }
}

private struct Setup: View {
    var body: some View {
        VStack(spacing: 0) {
            Heading(title: "Get Lamp ready", detail: "Two things to set up, then you can start.")
            VStack(spacing: 12) {
                card {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple's app-building tools").font(.system(size: 14, weight: .semibold))
                            Text("Installed and ready.").font(.system(size: 12.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("What builds your apps").font(.system(size: 14, weight: .semibold))
                        ForEach(["Claude", "ChatGPT", "OpenRouter", "Another provider", "A model on this Mac"], id: \.self) { name in
                            HStack(spacing: 10) {
                                Circle().strokeBorder(name == "Claude" ? Steps.ink : .black.opacity(0.2),
                                                      lineWidth: name == "Claude" ? 5 : 1.2)
                                    .frame(width: 16, height: 16)
                                Text(name).font(.system(size: 13.5))
                                Spacer()
                                if name == "Claude" {
                                    Text("Signed in").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 560)
            .padding(.top, 26)
            Spacer()
        }
        .padding(.top, 90)
        .overlay { Footer(title: "Start building").frame(width: 1080) }
    }

    func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.black.opacity(0.07)))
            .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
    }
}

private struct Dots: View {
    let step: Double
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1..<3) { i in
                Capsule().fill(Steps.ink.opacity(abs(step - Double(i)) < 0.5 ? 0.8 : 0.18))
                    .frame(width: abs(step - Double(i)) < 0.5 ? 18 : 6, height: 6)
            }
        }
    }
}
