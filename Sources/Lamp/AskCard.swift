import SwiftUI

/// Questions and changeable assumptions from the builder, kept in the transcript as direct choices instead
/// of prose. Sending an answer uses an ordinary user message, so the conversation remains readable to every
/// engine and to someone returning to it later.
struct AskCard: View {
    let line: LogLine
    let dir: URL
    @ObservedObject private var store = Store.shared
    @State private var selections: [String?]
    @State private var customText: [String]
    @FocusState private var focusedCustomAnswer: Int?

    init(line: LogLine, dir: URL) {
        self.line = line
        self.dir = dir
        let payload = line.ask
        let saved = payload?.answers ?? payload?.questions.map(\.chosen) ?? []
        _selections = State(initialValue: saved)
        _customText = State(initialValue: Array(repeating: "", count: payload?.questions.count ?? 0))
    }

    private var payload: AskCardPayload? { line.ask }
    private var project: LampProject? { store.projects.first { $0.dir == dir } }

    var body: some View {
        if let payload {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(payload.questions.indices, id: \.self) { index in
                    question(payload.questions[index], at: index, payload: payload)
                }
                if !payload.isAssumption, !payload.isReadOnly, payload.questions.count > 1,
                   selections.count == payload.questions.count, selections.allSatisfy({ $0?.trimmed.isEmpty == false }) {
                    HStack {
                        Spacer()
                        Button("Send") { sendAnswers(payload) }
                            .keyboardShortcut(.return, modifiers: [])
                            .controlSize(.small)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        }
    }

    @ViewBuilder
    private func question(_ question: AskQuestion, at index: Int, payload: AskCardPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.question).font(.headline).fixedSize(horizontal: false, vertical: true)
            if payload.isReadOnly {
                let answer = payload.answers.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? question.chosen
                if let answer {
                    Label(answer, systemImage: "checkmark")
                        .font(.body).foregroundStyle(.secondary)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { choices(question, at: index, payload: payload) }
                    VStack(alignment: .leading, spacing: 6) { choices(question, at: index, payload: payload) }
                }
            }
        }
    }

    @ViewBuilder
    private func choices(_ question: AskQuestion, at index: Int, payload: AskCardPayload) -> some View {
        ForEach(question.options, id: \.self) { option in
            choice(option, question: question, at: index, payload: payload)
        }
        customAnswer(at: index, payload: payload)
    }

    private func choice(_ title: String, question: AskQuestion, at index: Int, payload: AskCardPayload) -> some View {
        let selected = selections.indices.contains(index) && selections[index] == title
        return Button {
            focusedCustomAnswer = nil
            customText[index] = ""
            selections[index] = title
            if payload.isAssumption {
                guard title != question.chosen else { return }
                sendAssumption(question, answer: title, at: index, payload: payload)
            } else if payload.questions.count == 1 {
                sendAnswers(payload)
            }
        } label: {
            Text(title)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func customAnswer(at index: Int, payload: AskCardPayload) -> some View {
        let focused = focusedCustomAnswer == index
        let hasAnswer = customText.indices.contains(index) && !customText[index].trimmed.isEmpty
        let expanded = focused || hasAnswer
        return TextField("Something else", text: Binding(
            get: { customText.indices.contains(index) ? customText[index] : "" },
            set: { value in
                guard customText.indices.contains(index), selections.indices.contains(index) else { return }
                customText[index] = value
                selections[index] = value.trimmed.nilIfEmpty
            }
        ), prompt: Text("Something else").foregroundColor(expanded ? .gray : .clear))
        .textFieldStyle(.plain)
        .foregroundStyle(focused ? Color.black : Color.primary)
        .overlay(alignment: .leading) {
            if !expanded {
                Text("Something else")
                    .foregroundStyle(Color.primary)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(minWidth: expanded ? 150 : nil, maxWidth: expanded ? .infinity : nil)
        .fixedSize(horizontal: !expanded, vertical: false)
        .background(focused ? Color.white : Color.primary.opacity(0.07), in: Capsule())
        .overlay {
            Capsule().strokeBorder(expanded ? Color.accentColor : Color.primary.opacity(0.12),
                                   lineWidth: expanded ? 2 : 1)
        }
        .layoutPriority(expanded ? 1 : 0)
        .focused($focusedCustomAnswer, equals: index)
        .onSubmit { submitCustom(at: index, payload: payload) }
        .animation(.easeInOut(duration: 0.16), value: expanded)
        .animation(.easeInOut(duration: 0.16), value: focused)
    }

    private func submitCustom(at index: Int, payload: AskCardPayload) {
        let answer = customText[index].trimmed
        guard !answer.isEmpty else { return }
        selections[index] = answer
        if payload.isAssumption {
            sendAssumption(payload.questions[index], answer: answer, at: index, payload: payload)
        } else if payload.questions.count == 1 {
            sendAnswers(payload)
        }
    }

    private func sendAnswers(_ payload: AskCardPayload) {
        guard let project, selections.count == payload.questions.count else { return }
        let answers = selections.compactMap { $0?.trimmed.nilIfEmpty }
        guard answers.count == payload.questions.count else { return }
        store.answerAsk(line.id, answers: answers,
                        message: AskCardPayload.answerMessage(questions: payload.questions, answers: answers), in: project)
    }

    private func sendAssumption(_ question: AskQuestion, answer: String, at index: Int, payload: AskCardPayload) {
        guard let project else { return }
        var answers = payload.questions.map { $0.chosen ?? "" }
        answers[index] = answer
        store.answerAsk(line.id, answers: answers,
                        message: AskCardPayload.assumptionMessage(question: question, answer: answer), in: project)
    }
}
