import SwiftUI

/// The agent's cards as the person sees them (`Talk`): questions to click through, in the chat or a page at a
/// time, and what a request made. Built like the setup card, so the chat reads as one thing.

/// Where a person is in a set of questions, and how an answer moves them on. The card and the page share it,
/// so leaving the page for the chat keeps what was already picked.
struct AskProgress: Equatable {
    var step = 0
    var answers: [Int: String] = [:]
    var typed = ""

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
                    AskSteps(ask: ask, progress: $progress, big: false) { store.answer(line, with: $0, in: project) }
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
                    ChipRow(options: question.options, chosen: progress.answers[index]) { progress.answers[index] = $0 }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            Divider()
            HStack {
                if progress.answers.isEmpty {
                    Button(Talk.youDecide) { store.answer(line, with: progress.all(ask.questions.count), in: project) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Send") { store.answer(line, with: progress.all(ask.questions.count), in: project) }
                    .buttonStyle(.borderedProminent)
                    .disabled(progress.answers.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

/// What was asked, and what was clicked, once a card is no longer waiting.
private struct Answered: View {
    let ask: Talk.Ask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(ask.questions.enumerated()), id: \.offset) { index, question in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(question.question).foregroundStyle(.secondary)
                    if let answers = ask.answers, index < answers.count {
                        Text(answers[index]).fontWeight(.medium)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One question at a time: its answers as tiles, a field for something else, and a way back. `big` is the
/// page's size.
struct AskSteps: View {
    let ask: Talk.Ask
    @Binding var progress: AskProgress
    let big: Bool
    let send: ([String]) -> Void

    private var count: Int { ask.questions.count }
    private var question: Talk.Question { ask.questions[min(progress.step, count - 1)] }

    var body: some View {
        VStack(alignment: big ? .center : .leading, spacing: big ? 22 : 12) {
            if count > 1 && !big {
                HStack {
                    Text("Question \(progress.step + 1) of \(count)").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    StepDots(count: count, current: progress.step)
                }
            }
            Text(question.question)
                .font(big ? .system(size: 30, weight: .bold) : .title3.weight(.semibold))
                .multilineTextAlignment(big ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            let columns = Array(repeating: GridItem(.flexible(), spacing: big ? 14 : 10),
                                count: question.options.count == 4 ? 2 : question.options.count)
            LazyVGrid(columns: columns, spacing: big ? 14 : 10) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                    OptionTile(option: option, chosen: progress.answers[progress.step] == option.title, big: big) {
                        pick(option.title)
                    }
                }
            }
            .frame(maxWidth: big ? 720 : .infinity)
            TextField("Something else…", text: $progress.typed)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .frame(maxWidth: big ? 420 : .infinity)
                .onSubmit { if !progress.typed.trimmed.isEmpty { pick(progress.typed.trimmed) } }
            HStack(spacing: 16) {
                if progress.step > 0 {
                    Button("Back") { progress.step -= 1 }
                }
                Button(Talk.youDecide) { pick(Talk.youDecide) }
                if !big { Spacer() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            if count > 1 && big { StepDots(count: count, current: progress.step) }
        }
        .padding(big ? 0 : 16)
        .animation(.snappy(duration: 0.2), value: progress.step)
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

/// An answer to click: a symbol, its name and a few words.
private struct OptionTile: View {
    let option: Talk.Option
    let chosen: Bool
    let big: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if big {
                    VStack(alignment: .leading, spacing: 12) {
                        symbol(size: 52)
                        words(centered: false)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                } else {
                    HStack(spacing: 10) {
                        symbol(size: 34)
                        words(centered: false)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(big ? 16 : 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: big ? 16 : 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: big ? 16 : 11, style: .continuous)
                .strokeBorder(chosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), lineWidth: chosen ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
    }

    @ViewBuilder private func symbol(size: CGFloat) -> some View {
        if let symbol = option.symbol {
            Image(systemName: symbol)
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: size, height: size)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        }
    }

    private func words(centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 1) {
            Text(option.title).font(big ? .title3.weight(.semibold) : .body.weight(.semibold))
            if let detail = option.detail {
                Text(detail).font(big ? .body : .callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(centered ? .center : .leading)
    }
}

/// A question's answers as chips on one line, or stacked when the card is too narrow for them.
private struct ChipRow: View {
    let options: [Talk.Option]
    let chosen: String?
    let pick: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    private var chips: some View {
        ForEach(Array(options.enumerated()), id: \.offset) { _, option in
            let on = chosen == option.title
            Button { pick(option.title) } label: {
                Text(option.title)
                    .lineLimit(1)
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

/// The questions before a new app, a page at a time over the chat. The chat's card stays underneath, and the
/// message box with it: "Answer in the Chat" goes back to them.
struct AskPage: View {
    let line: LogLine
    let project: LampProject
    let leave: () -> Void
    @ObservedObject private var store = Store.shared
    @State private var progress = AskProgress()

    var body: some View {
        if let ask = line.ask {
            ZStack(alignment: .bottom) {
                Color(nsColor: .textBackgroundColor)
                AskSteps(ask: ask, progress: $progress, big: true) { store.answer(line, with: $0, in: project) }
                    .padding(.horizontal, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Button("Answer in the Chat", action: leave)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 22)
            }
            .transition(.opacity)
        }
    }
}

/// What a request made: its picture, one sentence, and what the agent chose for the person, each with a
/// button for the other way. The buttons are there while they'd still do what they say: until the person asks
/// for something else.
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
                if isCurrent {
                    ForEach(Array(result.guesses.enumerated()), id: \.offset) { _, guess in
                        row(guess.guess, detail: "Lamp chose this for you.", button: guess.instead) {
                            store.send(guess.request, to: project)
                        }
                    }
                    if let idea = result.idea {
                        row(idea.title, detail: idea.detail, button: "Add It") { store.send(idea.request, to: project) }
                    }
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ title: String, detail: String?, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                Button(button, action: action)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
    }
}
