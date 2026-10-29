import SwiftUI
import AppKit

extension ChatLook {
    /// What a command does and how risky it is, in plain words for people who don't read shell commands.
    public struct Explanation: Codable, Equatable {
        public var summary: String
        /// "low", "medium" or "high"; empty when nothing rated it.
        public var risk: String
        public var why: String

        public init(summary: String, risk: String, why: String) {
            self.summary = summary
            self.risk = risk
            self.why = why
        }
    }

    /// A step the agent wants to take that Lamp won't take without the person, explained in plain words.
    /// Nothing runs until they answer.
    ///
    /// Most people asked this have never read a shell command, so the card is built to be decided without one, and
    /// holds only the decision: what the step does, its risk, and the two answers. Everything that helps decide
    /// (why Lamp is asking, what the person asked for to weigh it against, that saying no is safe, the exact command)
    /// is in a popover from How to Decide (`ApprovalHelp`), where there's room to say it.
    public struct ApprovalCard: View {
        let title: String
        let command: String
        let explanation: Explanation?
        /// What the person asked for in the request this step is part of, in their words: what it's weighed against.
        let request: String?
        /// Why Lamp is asking rather than letting the step run.
        let whyAsked: String?
        let onAllow: () -> Void
        let onAllowAll: () -> Void
        let onDeny: () -> Void
        @State private var helping = false

        public init(title: String, command: String, explanation: Explanation?, request: String? = nil, whyAsked: String? = nil,
                    onAllow: @escaping () -> Void, onAllowAll: @escaping () -> Void, onDeny: @escaping () -> Void) {
            self.title = title
            self.command = command
            self.explanation = explanation
            self.request = request
            self.whyAsked = whyAsked
            self.onAllow = onAllow
            self.onAllowAll = onAllowAll
            self.onDeny = onDeny
        }

        private var highRisk: Bool { explanation?.risk == "high" }
        private var rated: Bool { !(explanation?.risk.isEmpty ?? true) }

        public var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                header
                // Beside How to Decide where there's room for both; in the wand's narrow panel, the buttons share
                // the card's width and How to Decide goes under them.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        howToDecide
                        Spacer(minLength: 0)
                        buttons(filling: false)
                    }
                    VStack(spacing: 12) {
                        buttons(filling: true)
                        howToDecide.frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
            .background(Paper.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Paper.rule))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }

        /// What's asked and how risky it is: enough to decide on for most steps.
        private var header: some View {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: highRisk ? "exclamationmark.shield.fill" : "hand.raised.fill")
                        .foregroundStyle(rated ? ApprovalHelp.color(of: explanation?.risk) : Paper.ink)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                // No fixedSize on these: it makes SwiftUI size the text for its narrowest possible width, and that
                // height became the whole window's minimum, growing the window past the screen.
                if let explanation {
                    Text(explanation.summary).font(.title3.weight(.semibold))
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Working out what this does…").foregroundStyle(.secondary)
                    }
                }
                if let explanation, rated {
                    Text("\(explanation.risk.capitalized) risk")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(ApprovalHelp.color(of: explanation.risk))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// The safe answer is the prominent one where the step is risky, on Escape as well, and on the right where
        /// Allow is on every other card, so a click out of habit there says no.
        private func buttons(filling: Bool) -> some View {
            func label(_ text: String) -> some View {
                Text(text).frame(minWidth: 96, maxWidth: filling ? .infinity : nil)
            }
            return HStack(spacing: 8) {
                if highRisk {
                    Button(action: onAllow) { label("Allow") }
                    Button(role: .cancel, action: onDeny) { label("Don't Allow") }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .cancel, action: onDeny) { label("Don't Allow") }
                        .keyboardShortcut(.escape, modifiers: [])
                    Button(action: onAllow) { label("Allow") }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                }
            }
            .cardButtons()
        }

        private var howToDecide: some View {
            Button {
                helping.toggle()
            } label: {
                Label("How to Decide", systemImage: "questionmark.circle")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHand()
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize()
            .popover(isPresented: $helping, arrowEdge: .top) {
                ApprovalHelp(command: command, explanation: explanation, request: request, whyAsked: whyAsked,
                             onAllowAll: { helping = false; onAllowAll() })
            }
        }
    }

    /// How to Decide's popover: what the step does and could reach, why Lamp stopped for it, how to weigh it
    /// against what the person asked for, and what saying no costs (nothing). Then the exact command for those who
    /// read them, and, for a step that isn't risky, allowing the rest of the request.
    public struct ApprovalHelp: View {
        let command: String
        let explanation: Explanation?
        let request: String?
        let whyAsked: String?
        let onAllowAll: () -> Void

        public init(command: String, explanation: Explanation?, request: String?, whyAsked: String?, onAllowAll: @escaping () -> Void) {
            self.command = command
            self.explanation = explanation
            self.whyAsked = whyAsked
            self.request = request.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
            self.onAllowAll = onAllowAll
        }

        public static let width: CGFloat = 360

        private var highRisk: Bool { explanation?.risk == "high" }
        private var rated: Bool { !(explanation?.risk.isEmpty ?? true) }

        /// The same green, yellow and red as app icons' backgrounds (Lamp's `Icons.backgrounds`). The icon
        /// yellow is too pale to read on a light background, so light mode gets a darker shade of it.
        static func color(of risk: String?) -> Color {
            switch risk {
            case "low": return Color(nsColor: NSColor(srgbRed: 0x28 / 255, green: 0xA7 / 255, blue: 0x45 / 255, alpha: 1))
            case "high": return Color(nsColor: NSColor(srgbRed: 0xE0 / 255, green: 0x30 / 255, blue: 0x2A / 255, alpha: 1))
            case "medium":
                let yellow = NSColor(srgbRed: 1, green: 0xC4 / 255, blue: 0, alpha: 1)
                return Color(nsColor: NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? yellow : yellow.blended(withFraction: 0.35, of: .black) ?? yellow
                })
            default: return .secondary
            }
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                if let explanation, rated {
                    section("\(explanation.risk.capitalized) risk", color: Self.color(of: explanation.risk)) {
                        Text(explanation.why.isEmpty ? explanation.summary : explanation.why)
                    }
                }
                // Said by Lamp, which knows why it asked: a check, the setting, a file outside the app. The rating
                // can't say it, since a low-risk step is asked about too when the setting asks about every command.
                section("Why you're asked") {
                    Text(whyAsked ?? "Lamp stops the agent for your OK before a step it won't take on its own.")
                }
                section("How to decide") {
                    if let request {
                        Text("You asked: “\(request)”")
                            .lineLimit(3)
                            .foregroundStyle(.secondary)
                    }
                    advice("checkmark.circle.fill", .green, allowAdvice)
                    advice("xmark.circle.fill", .secondary, "Not sure? Don't Allow. Nothing changes, and the agent is told so it can try another way.")
                }
                section("Exactly what it asked to do") {
                    // A long command scrolls rather than growing the popover off the screen. The limit goes on a
                    // scroll view sized to what's in it, so a one-line command takes one line.
                    ScrollView {
                        Text(command)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 120)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
                // Risky steps are asked about one at a time.
                if !highRisk {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Text("Asked again and again?").foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("Allow All Until Done", action: onAllowAll)
                            .help("Every step the agent asks for runs without asking until this request is done.")
                    }
                    .font(.callout)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            .frame(width: Self.width, alignment: .leading)
        }

        private var allowAdvice: String {
            if highRisk { return "Allow only if you know why it's needed. A step like this can be hard to undo." }
            return request == nil ? "Allow if it sounds like part of what you asked for." : "Allow if it sounds like a step toward that."
        }

        private func section<Content: View>(_ heading: String, color: Color = .primary, @ViewBuilder content: () -> Content) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(heading).font(.headline).foregroundStyle(color).accessibilityAddTraits(.isHeader)
                content()
            }
            .font(.callout)
        }

        private func advice(_ symbol: String, _ color: Color, _ text: String) -> some View {
            Label {
                Text(text)
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
        }
    }
}
