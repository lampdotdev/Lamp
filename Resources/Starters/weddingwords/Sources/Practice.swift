import SwiftUI

struct PracticeView: View {
    @EnvironmentObject var coach: WeddingCoach
    @StateObject private var talk = TableTalk()
    @State private var input = ""
    @State private var translation = ""
    @State private var feedback = ""
    @State private var showEnglish = false
    @StateObject private var speech = WeddingSpeech()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A seat next to Marco’s mother").font(.largeTitle.weight(.medium))
            Text("Rehearsal dinner · warm company, real conversation, zero vocabulary quizzes.").foregroundStyle(.secondary)
            Picker("Rehearse", selection: $coach.selected) {
                ForEach(0..<3, id: \.self) { Text(WeddingCoach.milestones[$0]).tag($0) }
            }.pickerStyle(.menu).onChange(of: coach.selected) { _, value in
                talk.open(value)
                feedback = ""; translation = talk.turns.last?.english ?? ""
                speech.stop(); speech.stopPlayback(); input = ""
            }.disabled(talk.busy || speech.speaking || speech.listening)
            if talk.busy {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("She’s getting her words together…").font(.headline)
                        Text("This can take a little while. Your turn comes after she speaks.").font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            if talk.turns.isEmpty {
                ContentUnavailableView("Meet her here first", systemImage: "fork.knife", description: Text("She’ll speak Italian. You can ask for a slower repeat, make mistakes, and try again. This is a fictional rehearsal, not a prediction of her personality."))
                    .frame(maxHeight: .infinity)
                if !talk.busy {
                    Button("Take my seat", systemImage: "bubble.left") { Task { await reply() } }.buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(talk.turns) { turn in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(turn.who).font(.caption.bold()).foregroundStyle(.secondary)
                                Text(turn.text).font(.title3).textSelection(.enabled)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(turn.who == "You" ? Color.terracotta.opacity(0.08) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                HStack {
                    Button("Hear her again", systemImage: "speaker.wave.2") { speech.say(talk.turns.last?.text ?? "", slow: true) }.disabled(talk.busy || speech.speaking || speech.listening || talk.awaitsHer)
                    Toggle("Show English", isOn: $showEnglish).toggleStyle(.checkbox)
                    Spacer()
                    Button("New rehearsal") { talk.clear(); feedback = ""; translation = ""; input = "" }.disabled(talk.busy || speech.speaking || speech.listening)
                }
                if showEnglish { Text(translation).foregroundStyle(.secondary) }
                if speech.speaking {
                    HStack {
                        Label("Listen to her first", systemImage: "speaker.wave.2.fill").font(.headline)
                        Spacer()
                        Button("Skip audio") { speech.stopPlayback() }
                    }.padding(16).background(Color.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                } else if talk.awaitsHer && !talk.busy {
                    Button("Try again", systemImage: "arrow.clockwise") { Task { await reply() } }.buttonStyle(.borderedProminent)
                } else if !talk.busy {
                    if !feedback.isEmpty { Label(feedback, systemImage: "heart.text.clipboard").padding(14).background(Color.terracotta.opacity(0.06), in: RoundedRectangle(cornerRadius: 10)) }
                    Text("Now it’s your turn").font(.headline)
                    SpeakingInput(speech: speech, text: $input)
                    Button("Send my reply", systemImage: "arrow.up.bubble") { let words = input; input = ""; Task { await reply(words) } }.buttonStyle(.borderedProminent).disabled(speech.listening || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if !talk.error.isEmpty { Text(talk.error).foregroundStyle(.red) }
        }.padding(28).navigationTitle("At the table")
        .task {
            if coach.selected > 2 { coach.selected = coach.weakest < 3 ? coach.weakest : 0 }
            talk.open(coach.selected)
            translation = talk.turns.last?.english ?? ""
        }
        .onDisappear { talk.leave(); speech.stop(); speech.stopPlayback() }
    }
    /// Sends `words`, or with none the reply still waiting for her (Try again), or asks for her greeting.
    @MainActor func reply(_ words: String? = nil) async {
        guard !talk.busy, !speech.speaking, !speech.listening else { return }
        speech.stop()
        let replying = words != nil || talk.awaitsHer
        let context = "Milestone: \(WeddingCoach.milestones[min(coach.selected, 2)]). Coach confidence: \(coach.state.scores[coach.selected] ?? 0)/5. Mother: \(coach.state.mother). Sister: \(coach.state.sister)."
        guard let result = await talk.ask(words, as: coach.state.mother, context: context) else { return }
        translation = result.translation; feedback = result.coaching
        coach.state.phrase = result.phrase; coach.state.meaning = result.meaning
        if replying { coach.record(coach.selected, score: result.score) } else { coach.save() }
        speech.say(result.italian)
    }
}
