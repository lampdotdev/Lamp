import SwiftUI

/// The agent's cards as the person sees them (`Talk`): questions to click through in the chat, and what a
/// request made. Built like the setup card, so the chat reads as one thing.

/// Where a person is in a set of questions, and how an answer moves them on.
struct AskProgress: Equatable {
    var step = 0
    var answers: [Int: String] = [:]
    var typed = ""
    /// With every question on one card, what's typed for each instead of picking one of its chips.
    var own: [Int: String] = [:]

    /// Takes what's typed as a question's answer; emptied, the question is unanswered again.
    mutating func type(_ text: String, for question: Int) {
        own[question] = text
        answers[question] = text.trimmed.nilIfEmpty
    }

    /// Takes a chip as a question's answer, in place of anything typed for it.
    mutating func choose(_ answer: String, for question: Int) {
        own[question] = nil
        answers[question] = answer
    }

    /// Takes an answer for the question showing. True when that was the last one.
    mutating func take(_ answer: String, of count: Int) -> Bool {
        answers[step] = answer
        typed = ""
        guard step < count - 1 else { return true }
        step += 1
        return false
    }

    /// Every question's answer, with the ones left out given to Lamp.
    func all(_ count: Int) -> [String] { (0..<count).map { answers[$0] ?? Talk.youDecide } }
}

/// A set of questions in the chat. Open, it's answered by clicking; after that it shows what was chosen, or
/// just what was asked when the person typed their answer instead.
struct AskCard: View {
    let line: LogLine
    let dir: URL
    let isOpen: Bool
    @ObservedObject private var store = Store.shared
    @State private var progress = AskProgress()

    var body: some View {
        if let ask = line.ask, let project = store.projects.first(where: { $0.dir == dir }) {
            Group {
                if !isOpen {
                    Answered(ask: ask)
                } else if ask.layout == .together && ask.questions.count > 1 {
                    together(ask, project)
                } else {
                    AskSteps(ask: ask, progress: $progress) { answers in withAnimation(.snappy(duration: 0.3)) { store.answer(line, with: answers, in: project) } }
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Every question at once, each answered by a chip.
    private func together(_ ask: Talk.Ask, _ project: LampProject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ask.questions.enumerated()), id: \.offset) { index, question in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.question).font(.headline)
                    ChipRow(options: question.options, chosen: progress.answers[index],
                            own: Binding(get: { progress.own[index] ?? "" }, set: { progress.type($0, for: index) })) {
                        progress.choose($0, for: index)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            Divider()
            HStack {
                if progress.answers.isEmpty {
                    Button(Talk.youDecide) { withAnimation(.snappy(duration: 0.3)) { store.answer(line, with: progress.all(ask.questions.count), in: project) } }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Send") { withAnimation(.snappy(duration: 0.3)) { store.answer(line, with: progress.all(ask.questions.count), in: project) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(progress.answers.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

/// A card that's no longer waiting, folded where it was: the answers that were clicked, or, when the person
/// typed their own answer instead, what was asked (their message under it is the answer).
private struct Answered: View {
    let ask: Talk.Ask

    var body: some View {
        Group {
            if let answers = ask.answers {
                Label {
                    Text(answers.joined(separator: " · ")).fontWeight(.medium)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .help(ask.questions.map(\.question).joined(separator: "\n"))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(ask.questions.enumerated()), id: \.offset) { _, question in
                        Text(question.question).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One question at a time: its answers as tiles, a field for something else, and a way back.
///
/// The card is laid out for all its questions at once and shows one: its height is the tallest question's,
/// and the field and the links under the tiles never move. A card that changed size from one question to the
/// next would slide what's about to be clicked out from under the pointer.
struct AskSteps: View {
    let ask: Talk.Ask
    @Binding var progress: AskProgress
    let send: ([String]) -> Void
    /// Off for a moment after the question changes, so the second click of a double-click doesn't answer
    /// the next question with whatever tile arrived under the pointer.
    @State private var armed = true

    private var count: Int { ask.questions.count }
    private var step: Int { min(progress.step, count - 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if count > 1 {
                HStack {
                    Text("Question \(step + 1) of \(count)").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    StepDots(count: count, current: step)
                }
            }
            every { question, _ in
                Text(question.question)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            every { question, index in
                let columns = Array(repeating: GridItem(.flexible(), spacing: 10),
                                    count: question.options.count == 4 ? 2 : question.options.count)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                        OptionTile(option: option, chosen: progress.answers[index] == option.title) {
                            pick(option.title)
                        }
                    }
                }
            }
            .allowsHitTesting(armed)
            TextField("Something else…", text: $progress.typed)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .onSubmit { if !progress.typed.trimmed.isEmpty { pick(progress.typed.trimmed) } }
            HStack(spacing: 16) {
                Button(Talk.youDecide) { pick(Talk.youDecide) }
                if step > 0 {
                    Button("Back") { progress.step -= 1 }
                }
                Spacer()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .allowsHitTesting(armed)
        }
        .padding(16)
        .task(id: step) {
            guard step > 0 || !armed else { return }
            armed = false
            try? await Task.sleep(for: .seconds(0.4))
            armed = true
        }
    }

    /// Every question's version of one part of the card, stacked, with only the current one there to see,
    /// click or read aloud: the part takes the size of the largest.
    private func every<Part: View>(@ViewBuilder _ part: @escaping (Talk.Question, Int) -> Part) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(ask.questions.enumerated()), id: \.offset) { index, question in
                part(question, index)
                    .opacity(index == step ? 1 : 0)
                    .allowsHitTesting(index == step)
                    .accessibilityHidden(index != step)
            }
        }
    }

    private func pick(_ answer: String) {
        if progress.take(answer, of: count) { send(progress.all(count)) }
    }
}

/// The welcome's dots: a pill for the step showing.
private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { step in
                Capsule().fill(step <= current ? Color.primary.opacity(0.8) : Color.primary.opacity(0.15))
                    .frame(width: step == current ? 20 : 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// An answer to click: its symbol, its name and a few words.
private struct OptionTile: View {
    let option: Talk.Option
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol = option.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title).fontWeight(.semibold)
                    if let detail = option.detail {
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(chosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), lineWidth: chosen ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
    }
}

/// A question's answers as chips on one line, or stacked when the card is too narrow for them.
private struct ChipRow: View {
    let options: [Talk.Option]
    let chosen: String?
    /// The person's own answer, typed beside the chips. Nil where there is nothing to type: a choice
    /// between the two ways something was built.
    var own: Binding<String>? = nil
    let pick: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips; field }
            VStack(alignment: .leading, spacing: 6) { chips; field }
        }
    }

    @ViewBuilder
    private var field: some View {
        if let own {
            let typed = !own.wrappedValue.trimmed.isEmpty
            TextField("Something else…", text: own)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(minWidth: 140)
                .background(Color(nsColor: .textBackgroundColor), in: Capsule())
                .overlay(Capsule().strokeBorder(typed ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), lineWidth: typed ? 2 : 1))
        }
    }

    private var chips: some View {
        ForEach(Array(options.enumerated()), id: \.offset) { _, option in
            let on = chosen == option.title
            Button { pick(option.title) } label: {
                HStack(spacing: 6) {
                    if let symbol = option.symbol {
                        Image(systemName: symbol).foregroundStyle(on ? Color.white : Color.accentColor)
                    }
                    Text(option.title).lineLimit(1)
                }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(nsColor: .textBackgroundColor)), in: Capsule())
                    .overlay(Capsule().strokeBorder(.quaternary))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}

/// What a request made: its picture and one sentence, then rows. A new app's are what the agent chose for the
/// person, each with a button for the other way; an ordinary change's are the new things and where to find
/// them, and what the agent didn't try as something to try. The rows with buttons are there while they'd
/// still do what they say, until the person asks for something else; what's new stays, since it stays true.
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
                    Text(result.summary).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(14)
                ForEach(Array((result.news ?? []).enumerated()), id: \.offset) { _, news in
                    row(news.what, detail: news.place)
                }
                // What the agent chose is the chip that's on, and the other way is the chip beside it: one
                // click turns it. A guess that was turned stays on the card as what the person chose.
                ForEach(Array(result.guesses.enumerated()), id: \.offset) { index, guess in
                    let turned = result.switched?.contains(index) == true
                    if isCurrent && result.switched == nil {
                        chosen(guess) { store.switchGuess(index, on: line, in: project) }
                    } else if turned {
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
                if isCurrent {
                    if let idea = result.idea {
                        row(idea.title, detail: idea.detail, button: "Add It") { store.send(idea.request, to: project) }
                    }
                    if let untried = result.untried {
                        row(untried, detail: "Lamp hasn't tried this yet.", button: "Try It") {
                            store.send(Talk.tryRequest(untried), to: project)
                        }
                    }
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chosen(_ guess: Talk.Guess, turn: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Divider()
            ChipRow(options: [Talk.Option(title: guess.guess), Talk.Option(title: guess.instead)], chosen: guess.guess) {
                if $0 == guess.instead { turn() }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
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
