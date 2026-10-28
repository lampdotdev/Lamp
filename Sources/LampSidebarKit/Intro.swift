import SwiftUI
import AppKit

/// An idea's icon: its symbol on a squircle, like an app icon. Quiet gray until it's `lit` (hovered or
/// chosen), when it takes its own color.
public struct IdeaIcon: View {
    let symbol: String
    let hue: Double
    var size: CGFloat
    var lit: Bool

    public init(symbol: String, hue: Double, size: CGFloat = 44, lit: Bool = false) {
        self.symbol = symbol
        self.hue = hue
        self.size = size
        self.lit = lit
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        ZStack {
            shape.fill(lit ? AnyShapeStyle(LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 1),
                                                                  Color(hue: hue, saturation: 0.75, brightness: 0.88)],
                                                         startPoint: .top, endPoint: .bottom))
                           : AnyShapeStyle(Color(white: 0.93)))
            shape.strokeBorder(lit ? .white.opacity(0.35) : .black.opacity(0.05), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(lit ? Color.white : Color(white: 0.45))
        }
        .frame(width: size, height: size)
        .shadow(color: lit ? Color(hue: hue, saturation: 0.7, brightness: 0.7).opacity(0.25) : .clear,
                radius: size * 0.16, y: size * 0.08)
        .animation(.easeOut(duration: 0.2), value: lit)
    }
}

extension ChatLook {
    /// A new wish's empty chat, in the middle of it: its icon, its name to change in place (or, for a wish not named
    /// yet, what would make the person's day easier), what to do, and ideas to start from, one under another in a
    /// narrow chat, which a click puts in the message box. Drawn from plain values, so the gallery shows it as it is.
    public struct Intro: View {
        let intro: SidebarIntro
        let rename: (String) -> Void
        let choose: (String) -> Void
        let more: () -> Void
        @State private var name = ""
        @State private var hovered: String?
        @FocusState private var editing: Bool

        public init(intro: SidebarIntro, rename: @escaping (String) -> Void, choose: @escaping (String) -> Void,
                    more: @escaping () -> Void) {
            self.intro = intro
            self.rename = rename
            self.choose = choose
            self.more = more
        }

        public var body: some View {
            VStack(spacing: 14) {
                Group {
                    if let data = intro.icon, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().interpolation(.high)
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.quaternary)
                    }
                }
                .frame(width: 96, height: 96)
                if let current = intro.name {
                    TextField("Name", text: $name, prompt: Text(intro.namePrompt))
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .focused($editing)
                        .onSubmit(commit)
                        .disabled(!intro.canRename)
                        .help("Rename this wish")
                        .onAppear { name = current }
                        .onChange(of: current) { if !editing { name = current } }
                        .onChange(of: editing) { if !editing { commit() } }
                } else {
                    Text("What would make your day easier, or more fun?")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                Text(intro.line)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !intro.ideas.isEmpty { ideas.padding(.top, 14) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }

        private var ideas: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Need inspiration?").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: more) {
                        HStack(spacing: 5) {
                            Image(systemName: "lightbulb")
                            Text("Show me others")
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                    ForEach(intro.ideas) { idea in
                        Button { choose(idea.text) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                IdeaIcon(symbol: idea.symbol, hue: idea.hue, size: 22, lit: hovered == idea.id)
                                // Every tile keeps room for three lines, so the grid doesn't change height when the
                                // ideas change.
                                Text(idea.text).font(.subheadline).lineLimit(3, reservesSpace: true)
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            // Just an outline, so the ideas stay quieter than what the person is writing.
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(hovered == idea.id ? 0.2 : 0.1), lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovered = $0 ? idea.id : (hovered == idea.id ? nil : hovered) }
                        .help("Puts this in the message box so you can change it before sending")
                    }
                }
            }
        }

        private func commit() {
            let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !typed.isEmpty, typed != intro.name else { return }
            rename(typed)
        }
    }

    /// Something every chat waits on (Apple's tools installing), above the chat, with its button.
    public struct Banner: View {
        let banner: SidebarBanner
        let action: () -> Void

        public init(banner: SidebarBanner, action: @escaping () -> Void) {
            self.banner = banner
            self.action = action
        }

        public var body: some View {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(banner.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let button = banner.button { Button(button, action: action).controlSize(.small) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    /// What a step printed, with Agent Details on: the first lines, and the rest a click away.
    public struct DetailText: View {
        let text: String
        @State private var expanded = false
        @State private var shownHeight: CGFloat = 0
        @State private var fullHeight: CGFloat = 0

        public init(_ text: String) { self.text = text }

        public var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(expanded ? nil : 12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                    // The same text with no limit, unseen, says how tall it would be in full: the button to show the
                    // rest appears only when there is a rest.
                    .background {
                        Text(text)
                            .font(.caption.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                    }
                if expanded || fullHeight > shownHeight + 1 {
                    Button(expanded ? "Show Less" : "Show Full Output") { expanded.toggle() }
                        .buttonStyle(.link)
                        .pointingHand()
                        .font(.caption)
                }
            }
            // Set in with the steps' words, past their symbols, as what the step above it said.
            .padding(.leading, ChatLook.stepIndent + ChatLook.stepSymbolRoom)
            .padding(.trailing, 32)
        }
    }

    /// A part's heading in a first build: its mark (a tick once done, its number until then), its title, how long it
    /// took, and a rule.
    public struct ChapterHeading: View {
        let state: SidebarBuild.State
        let number: Int
        let title: String
        var time: String?
        /// The folded build's line, which opens to its parts.
        var chevron: Bool?
        /// Lamp's own last part, marked as one no plan lists.
        var finishing: Bool
        var working: Bool

        public init(state: SidebarBuild.State, number: Int, title: String, time: String? = nil, chevron: Bool? = nil,
                    finishing: Bool = false, working: Bool = false) {
            self.state = state
            self.number = number
            self.title = title
            self.time = time
            self.chevron = chevron
            self.finishing = finishing
            self.working = working
        }

        public var body: some View {
            // Set as the steps under it are (their font, symbol column and indent), so a part reads as one of the
            // chat's lines rather than a heading above them: the rule and the mark say it's a part.
            HStack(spacing: 6) {
                mark.frame(width: 16, height: 16)
                // A long part wraps rather than losing its end; the rule takes what room is left.
                Text(title)
                    .foregroundStyle(state == .later ? AnyShapeStyle(.tertiary) : state == .now ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                if let time { Text(time).font(.caption).foregroundStyle(.tertiary).fixedSize() }
                if let chevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(chevron ? 90 : 0))
                }
                Rectangle().fill(.quaternary).frame(minWidth: 12, maxHeight: 1)
            }
            .font(ChatLook.stepFont)
            .padding(.leading, ChatLook.stepIndent)
            .contentShape(Rectangle())
            .padding(.top, 12).padding(.bottom, 4)
            .accessibilityElement(children: .combine)
        }

        /// Where a part's mark is centered, which the line down its steps goes through.
        static let markCentre = ChatLook.stepIndent + 8

        @ViewBuilder
        private var mark: some View {
            if working {
                ProgressView().controlSize(.mini)
            } else if state == .done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .green)
            } else if finishing {
                Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [2, 2])).foregroundStyle(.tertiary).padding(1)
            } else {
                let color: Color = state == .now ? .accentColor : .secondary
                Circle().strokeBorder(color.opacity(state == .now ? 1 : 0.5), lineWidth: 1.2).padding(1)
                    .overlay { Text("\(number)").font(.system(size: 9, weight: .semibold)).foregroundStyle(color.opacity(state == .now ? 1 : 0.7)) }
            }
        }
    }

    /// A new app's first build (`SidebarBuild`). What's under each part is drawn by the chat (`part`), given the part,
    /// which knows whether it's the one going on now.
    public struct BuildChapters<Part: View>: View {
        let build: SidebarBuild
        @ViewBuilder let part: (SidebarBuild.Part) -> Part

        public init(build: SidebarBuild, @ViewBuilder part: @escaping (SidebarBuild.Part) -> Part) {
            self.build = build
            self.part = part
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if build.folded {
                    // Made: each part is a fold of its own in the chat, as a finished turn's steps are, rather than
                    // the parts packed inside one fold for the whole build.
                    ForEach(Array(build.parts.enumerated()), id: \.offset) { index, piece in
                        PartFold(title: piece.title ?? build.foldTitle, time: piece.time, first: index == 0) {
                            part(piece)
                        }
                    }
                    if let answer = build.answer { ChatLook.AgentText(answer).padding(.top, 12) }
                } else {
                    chapters
                }
            }
        }

        /// A done part as one line, its tick, title and time, that opens to what was said and done in it.
        private struct PartFold<Content: View>: View {
            let title: String
            let time: String?
            let first: Bool
            @ViewBuilder let content: () -> Content
            @State private var open = false

            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { open.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .green).frame(width: 16)
                            Text(title).fixedSize(horizontal: false, vertical: true)
                            if let time { Text(time).font(.caption).foregroundStyle(.tertiary).fixedSize() }
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(open ? 90 : 0))
                        }
                        .font(ChatLook.stepFont)
                        .foregroundStyle(.secondary)
                        .padding(.leading, ChatLook.stepIndent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .help(open ? "Hide this part" : "Show this part")
                    if open {
                        content()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4).padding(.bottom, 8)
                            .transition(.opacity)
                    }
                }
                .padding(.top, first ? 0 : 8)
            }
        }

        private var chapters: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(build.parts.enumerated()), id: \.offset) { index, piece in
                    if let title = piece.title {
                        ChapterHeading(state: piece.state, number: index + 1, title: title, time: piece.time)
                        if piece.state != .later {
                            part(piece)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, ChatLook.stepSymbolRoom).padding(.bottom, 4)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(.quaternary).frame(width: 1.5).padding(.leading, ChapterHeading.markCentre - 0.75)
                                }
                        }
                    } else {
                        // No plan yet: what the agent has said and done so far.
                        part(piece)
                    }
                }
                ForEach(Array(build.sketch.enumerated()), id: \.offset) { index, title in
                    ChapterHeading(state: .later, number: index + 1, title: title)
                }
                // Lamp's own last part, which no plan lists: building the app and opening it.
                if let finishing = build.finishing {
                    ChapterHeading(state: finishing, number: 0, title: "Lamp builds and opens it", finishing: true,
                                   working: finishing == .now)
                    if finishing == .now, let activity = build.finishingActivity {
                        ChatLook.ActivityText(activity, since: build.finishingSince ?? Date())
                            .font(ChatLook.stepFont).foregroundStyle(.secondary)
                            .padding(.leading, ChatLook.stepIndent + ChatLook.stepSymbolRoom)
                    }
                }
            }
        }
    }
}
