import SwiftUI
import LampSidebarKit

/// The agent's cards as the person sees them (`Talk`): questions to click through in the chat, and what a
/// request made. Built like the setup card, so the chat reads as one thing.

/// How far each open card has been answered, by its line. Kept apart from the card's view because the same
/// card is drawn in Lamp's window and in the chat inside the app's (`SidebarServer`): an answer begun in one
/// is carried on in the other, not started over. `changed` counts the changes made in Lamp's window, which
/// the chat beside the app takes up; its own come back with the count they were sent against.
@MainActor
final class AskProgresses: ObservableObject {
    static let shared = AskProgresses()
    @Published private var progress: [UUID: AskProgress] = [:]
    private(set) var changed: [UUID: Int] = [:]

    subscript(line: UUID) -> AskProgress { progress[line] ?? AskProgress() }

    func binding(for line: UUID) -> Binding<AskProgress> {
        Binding(get: { self[line] }, set: { self.progress[line] = $0; self.changed[line, default: 0] += 1 })
    }

    /// From the chat beside the app, which already shows it.
    func set(_ value: AskProgress, for line: UUID) { progress[line] = value }
}

/// A set of questions in the chat. Open, it's answered by clicking (`QuestionCard`, the same card the chat
/// beside the app draws); after that it shows what was chosen, or just what was asked when the person typed
/// their answer instead.
struct AskCard: View {
    let line: LogLine
    let dir: URL
    let isOpen: Bool
    @ObservedObject private var store = Store.shared
    @ObservedObject private var progresses = AskProgresses.shared

    var body: some View {
        if let ask = line.ask, let project = store.projects.first(where: { $0.dir == dir }) {
            if !isOpen {
                AnsweredQuestions(folded: ask.folded, questions: ask.questions.map(\.question))
            } else {
                QuestionCard(questions: ask.cardQuestions, together: ask.layout == .together, progress: progresses.binding(for: line.id)) { answers in
                    withAnimation(.snappy(duration: 0.3)) { store.answer(line, with: answers, in: project) }
                }
            }
        }
    }
}

extension Talk.Ask {
    /// The questions as the card draws them, in Lamp's window and beside the app.
    var cardQuestions: [CardQuestion] {
        questions.map { CardQuestion(question: $0.question, options: $0.options.map { CardOption(title: $0.title, detail: $0.detail, symbol: $0.symbol) }) }
    }
}

/// What a request made: its picture and one sentence, a new app's as much as a change's. Rows under the picture
/// read as captions of it, and a new app's guesses and idea there made a form to go through when it's the app
/// the person wants to try. What the agent didn't try is a row to try it, there while it would still do what it
/// says, until the person asks for something else.
struct ResultCard: View {
    let line: LogLine
    let dir: URL
    let isCurrent: Bool
    @ObservedObject private var store = Store.shared

    var body: some View {
        if let result = line.result, let project = store.projects.first(where: { $0.dir == dir }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    if let version = result.version,
                       let picture = NSImage(contentsOf: Versions.pictureURL(in: project, for: version)) {
                        Image(nsImage: picture)
                            .resizable().scaledToFit()
                            .frame(maxWidth: 150, maxHeight: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.quaternary))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.summary).font(.headline).fixedSize(horizontal: false, vertical: true)
                        // A card saved while it had rows of what's new: where to find each, as part of its
                        // sentence rather than rows under the picture.
                        ForEach(Array((result.news ?? []).enumerated()), id: \.offset) { _, news in
                            Text("\(news.what): \(news.place)").font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                // A card saved while guesses were buttons keeps the one the person turned, as what they chose:
                // the chat doesn't show the message that click sent (`Talk.shows`).
                ForEach(Array(result.guesses.enumerated()), id: \.offset) { index, guess in
                    if result.switched?.contains(index) == true {
                        Divider()
                        Label {
                            Text(guess.instead).fontWeight(.medium)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if isCurrent, let untried = result.untried {
                    row(untried, detail: "Lamp hasn't tested this yet.", button: "Have Lamp Test It") {
                        store.send(Talk.tryRequest(untried), to: project)
                    }
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ title: String, detail: String?, button: String? = nil, action: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let button { Button(button, action: action) }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
    }
}
