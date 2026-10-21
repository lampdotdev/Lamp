import SwiftUI

/// The tag, turned over: everything about one bottle, editable, and the way to retire it.
struct BottleDetail: View {
    let id: String
    var startRetiring = false
    var onDelete: () -> Void = {}

    @EnvironmentObject var shelf: Shelf
    @StateObject private var dictation = Dictation()
    @State private var retiring = false
    @State private var verdict = ""
    @State private var choosePhoto = false

    private let quickVerdicts = ["buy again", "never again", "fine in a pinch", "gone too soon"]

    var body: some View {
        let b = shelf.binding(id)
        VStack(alignment: .leading, spacing: 14) {
            header(b)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Paper.caption("Heat").frame(width: 44, alignment: .leading)
                    PepperRow(value: b.wrappedValue.intensity, size: 16) { b.wrappedValue.heat = Double($0) }
                    Spacer(minLength: 0)
                    Text("\(b.wrappedValue.intensity)").font(Hand.font(18)).foregroundStyle(Paper.ink)
                }
                HStack(spacing: 10) {
                    Paper.caption("Love").frame(width: 44, alignment: .leading)
                    StarRow(value: b.wrappedValue.score, size: 16) { value in
                        b.wrappedValue.stars = value
                        b.wrappedValue.rating = nil
                    }
                    Spacer(minLength: 0)
                    Text(b.wrappedValue.score.map(String.init) ?? "–").font(Hand.font(18)).foregroundStyle(Paper.ink)
                }
            }

            Paper.rule

            VStack(alignment: .leading, spacing: 10) {
                PaperField(label: "Peppers", text: Binding(get: { b.wrappedValue.peppers.joined(separator: ", ") },
                                                           set: { b.wrappedValue.peppers = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }))
                PaperField(label: "Tastes like", text: b.tastes, multiline: true)
                PaperField(label: "Notes", text: b.tag, prompt: "eggs, tacos, life…")
                if !b.wrappedValue.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Paper.caption("Ingredients")
                        Text(b.wrappedValue.ingredients)
                            .font(.system(size: 11, design: .serif).italic())
                            .foregroundStyle(Paper.ink.opacity(0.7))
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            history(b.wrappedValue)

            Paper.rule

            if b.wrappedValue.isRetired {
                retiredControls(b)
            } else if retiring {
                retireForm
            } else {
                HStack(spacing: 8) {
                    Button("Finished it…") { withAnimation { retiring = true } }
                        .buttonStyle(InkButtonStyle())
                    Menu {
                        Button("Find the Real Label") { LabelFinder.shared.find(id, force: true) }
                        Button("Use My Photo…") { choosePhoto = true }
                    } label: {
                        Text("Label").font(.system(size: 12, weight: .semibold, design: .serif))
                    }
                    .menuStyle(.button)
                    .buttonStyle(InkButtonStyle())
                    .menuIndicator(.hidden)
                    .fixedSize()
                    Spacer()
                    deleteButton
                }
            }
        }
        .padding(20)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.colorScheme, .light)
        .tint(Paper.red)
        .onAppear { retiring = startRetiring }
        .fileImporter(isPresented: $choosePhoto, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result, let image = NSImage(contentsOf: url) else { return }
            Task {
                guard let cut = await Cutout.make(image), let name = BottleImages.save(cut), var bottle = shelf.bottle(id) else { return }
                if bottle.hasPhoto, let old = bottle.imageName { BottleImages.remove(old) }
                bottle.imageName = name
                bottle.labelTried = true
                shelf.update(bottle)
            }
        }
        .onChange(of: dictation.text) { _, words in verdict = words }
    }

    private func header(_ b: Binding<Bottle>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: b.name, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Hand.font(22))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1...3)
                TextField("Maker", text: b.maker, prompt: Text("Who makes it"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Paper.ink.opacity(0.7))
                Menu {
                    ForEach(FlavorFamily.allCases) { family in
                        Button(family.title.capitalized) { b.wrappedValue.family = family.rawValue }
                    }
                } label: {
                    Text(b.wrappedValue.flavor.title.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .serif))
                        .kerning(1.2)
                        .foregroundStyle(Paper.red)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Paper.red, lineWidth: 1.5))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .rotationEffect(.degrees(-3))
                .padding(.top, 4)
                .help("Move it to another shelf")
            }
        }
    }

    private func history(_ b: Bottle) -> some View {
        Group {
            if let retired = b.retiredAt {
                Text("Finished \(retired.formatted(date: .abbreviated, time: .omitted)) · came home \(b.addedAt.formatted(date: .abbreviated, time: .omitted))")
            } else if let used = b.lastUsedAt {
                Text("Came home \(b.addedAt.formatted(.relative(presentation: .named))) · last splash \(used.formatted(.relative(presentation: .named)))")
            } else {
                Text("Came home \(b.addedAt.formatted(.relative(presentation: .named)))")
            }
        }
        .font(Hand.font(12))
        .foregroundStyle(Paper.ink.opacity(0.6))
    }

    private var retireForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The verdict?").font(Hand.font(20)).foregroundStyle(Paper.ink)
            HStack(alignment: .bottom) {
                PaperField(label: "In a few words", text: $verdict, prompt: "buy again, never again…")
                    .onSubmit(retire)
                Button { dictation.toggle() } label: {
                    Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                }
                .buttonStyle(InkButtonStyle(prominent: dictation.isListening))
                .help(dictation.isListening ? "Stop listening" : "Say it instead")
                .accessibilityLabel("Dictate verdict")
            }
            if let problem = dictation.problem { Text(problem).font(.caption).foregroundStyle(Paper.red) }
            HStack(spacing: 6) {
                ForEach(quickVerdicts, id: \.self) { v in
                    Button(v) { verdict = v }.buttonStyle(InkButtonStyle(small: true))
                }
            }
            HStack {
                Button("Not yet") { withAnimation { retiring = false } }.buttonStyle(InkButtonStyle())
                Spacer()
                Button("Retire it", action: retire)
                    .buttonStyle(InkButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func retire() {
        dictation.stop()
        shelf.retire(id, verdict: verdict.isEmpty ? "finished" : verdict)
    }

    private func retiredControls(_ b: Binding<Bottle>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PaperField(label: "Verdict", text: Binding(get: { b.wrappedValue.verdict ?? "" }, set: { b.wrappedValue.verdict = $0 }))
            HStack {
                Button("Back on the shelf") { shelf.unretire(id) }
                    .buttonStyle(InkButtonStyle())
                    .help("Bought another one")
                Spacer()
                deleteButton
            }
        }
    }

    private var deleteButton: some View {
        Button { onDelete() } label: { Image(systemName: "trash") }
            .buttonStyle(InkButtonStyle())
            .help("Remove this bottle")
            .accessibilityLabel("Remove bottle")
    }
}

/// The card stock and ink the detail card is made of.
enum Paper {
    static let color = Zine.cream
    static let ink = Zine.navy
    static let red = Zine.red

    static func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold, design: .serif))
            .kerning(1)
            .foregroundStyle(ink.opacity(0.55))
    }

    static var rule: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay(Line().stroke(ink.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }

    /// Warm card with a faint ruled texture and a darker, worn edge.
    static var background: some View {
        ZStack {
            color
            LinearGradient(colors: [.white.opacity(0.3), .clear, Zine.pink.opacity(0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .ignoresSafeArea()
    }

    struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

/// A field written on the card: a small printed caption, ink on a dotted line.
struct PaperField: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var multiline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Paper.caption(label)
            Group {
                if multiline {
                    TextField(label, text: $text, prompt: Text(prompt).foregroundStyle(Paper.ink.opacity(0.3)), axis: .vertical)
                        .lineLimit(1...3)
                } else {
                    TextField(label, text: $text, prompt: Text(prompt).foregroundStyle(Paper.ink.opacity(0.3)))
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .serif))
            .foregroundStyle(Paper.ink)
            .padding(.bottom, 3)
            .overlay(alignment: .bottom) {
                Paper.Line().stroke(Paper.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [1, 2])).frame(height: 1)
            }
        }
    }
}

/// Buttons that look stamped in ink on the card.
struct InkButtonStyle: ButtonStyle {
    var prominent = false
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 11 : 12, weight: .semibold, design: .serif))
            .foregroundStyle(prominent ? Paper.color : Paper.ink)
            .padding(.horizontal, small ? 8 : 11).padding(.vertical, small ? 3 : 5)
            .background(Capsule().fill(prominent ? Paper.red : Paper.ink.opacity(configuration.isPressed ? 0.12 : 0.04)))
            .overlay(Capsule().strokeBorder(prominent ? Paper.red : Paper.ink.opacity(0.55), lineWidth: 1.2))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .contentShape(Capsule())
    }
}
