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
            PageHeading(script: "a tavola", title: "A seat next to Marco’s mother", subtitle: "Rehearsal dinner · warm company, real conversation, zero vocabulary quizzes.")
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
                }.frame(maxWidth: .infinity, alignment: .leading).invitationCard(padding: 16, radius: 12)
            }
            if talk.turns.isEmpty {
                VStack(spacing: 14) {
                    MaiolicaPlate().frame(width: 150, height: 150).padding(.bottom, 6)
                    Text("Meet her here first").font(Look.serif(24))
                    Text("She’ll speak Italian. You can ask for a slower repeat, make mistakes, and try again. This is a fictional rehearsal, not a prediction of her personality.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    if !talk.busy {
                        Button("Take my seat", systemImage: "chair") { Task { await reply() } }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(talk.turns) { turn in
                            let mine = turn.who == "You"
                            VStack(alignment: .leading, spacing: 6) {
                                Engraved(turn.who, size: 10)
                                Text(turn.text).font(mine ? .title3 : Look.serif(20, italic: true)).textSelection(.enabled)
                            }
                            .padding(16)
                            .background(mine ? Look.wash : Look.card, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Look.ink.opacity(mine ? 0 : 0.15), lineWidth: 0.75))
                            .frame(maxWidth: 620, alignment: mine ? .trailing : .leading)
                            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
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
                    }.invitationCard(padding: 16, radius: 12)
                } else if talk.awaitsHer && !talk.busy {
                    Button("Try again", systemImage: "arrow.clockwise") { Task { await reply() } }.buttonStyle(.borderedProminent)
                } else if !talk.busy {
                    if !feedback.isEmpty { Label(feedback, systemImage: "heart.text.clipboard").frame(maxWidth: .infinity, alignment: .leading).invitationCard(padding: 14, radius: 12) }
                    Engraved("Now it’s your turn")
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
