import SwiftUI

struct ConversationTurn: Codable, Identifiable {
    var id = UUID()
    let who: String
    let text: String
}
struct RoleReply: Decodable {
    let italian: String
    let translation: String
    let coaching: String
    let score: Int
    let phrase: String
    let meaning: String
}
struct PracticeView: View {
    @EnvironmentObject var coach: WeddingCoach
    @State private var turns: [ConversationTurn] = []
    @State private var input = ""
    @State private var translation = ""
    @State private var feedback = ""
    @State private var busy = false
    @State private var error = ""
    @State private var showEnglish = false
    @StateObject private var speech = WeddingSpeech()
    @State private var requestID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A seat next to Marco’s mother").font(.largeTitle.weight(.medium))
            Text("Rehearsal dinner · warm company, real conversation, zero vocabulary quizzes.").foregroundStyle(.secondary)
            Picker("Rehearse", selection: $coach.selected) {
                ForEach(0..<3, id: \.self) { Text(WeddingCoach.milestones[$0]).tag($0) }
            }.pickerStyle(.menu).onChange(of: coach.selected) { _, value in
                turns = LampStore.load([ConversationTurn].self, from: "conversation-\(value)") ?? []
                feedback = ""; translation = ""
                speech.stop(); speech.stopPlayback(); input = ""
            }.disabled(busy || speech.speaking || speech.listening)
            if busy {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("She’s getting her words together…").font(.headline)
                        Text("This can take a little while. Your turn comes after she speaks.").font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            if turns.isEmpty {
                ContentUnavailableView("Meet her here first", systemImage: "fork.knife", description: Text("She’ll speak Italian. You can ask for a slower repeat, make mistakes, and try again. This is a fictional rehearsal, not a prediction of her personality."))
                    .frame(maxHeight: .infinity)
                if !busy {
                    Button("Take my seat", systemImage: "bubble.left") { Task { await reply(start: true) } }.buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(turns) { turn in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(turn.who).font(.caption.bold()).foregroundStyle(.secondary)
                                Text(turn.text).font(.title3).textSelection(.enabled)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(turn.who == "You" ? Color.terracotta.opacity(0.08) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                HStack {
                    Button("Hear her again", systemImage: "speaker.wave.2") { speech.say(turns.last?.text ?? "", slow: true) }.disabled(busy || speech.speaking || speech.listening || turns.last?.who == "You")
                    Toggle("Show English", isOn: $showEnglish).toggleStyle(.checkbox)
                    Spacer()
                    Button("New rehearsal") { turns = []; feedback = ""; translation = ""; input = ""; LampStore.save(turns, to: "conversation-\(coach.selected)") }.disabled(busy || speech.speaking || speech.listening)
                }
                if showEnglish { Text(translation).foregroundStyle(.secondary) }
                if speech.speaking {
                    HStack {
                        Label("Listen to her first", systemImage: "speaker.wave.2.fill").font(.headline)
                        Spacer()
                        Button("Skip audio") { speech.stopPlayback() }
                    }.padding(16).background(Color.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                } else if !busy {
                    if !feedback.isEmpty { Label(feedback, systemImage: "heart.text.clipboard").padding(14).background(Color.terracotta.opacity(0.06), in: RoundedRectangle(cornerRadius: 10)) }
                    Text("Now it’s your turn").font(.headline)
                    SpeakingInput(speech: speech, text: $input)
                    Button("Send my reply", systemImage: "arrow.up.bubble") { Task { await reply(start: false) } }.buttonStyle(.borderedProminent).disabled(speech.listening || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }.padding(28).navigationTitle("At the table")
        .task {
            if coach.selected > 2 { coach.selected = coach.weakest < 3 ? coach.weakest : 0 }
            turns = LampStore.load([ConversationTurn].self, from: "conversation-\(coach.selected)") ?? []
        }
        .onDisappear { requestID = UUID(); busy = false; speech.stop(); speech.stopPlayback() }
    }
    @MainActor func reply(start: Bool) async {
        guard !busy, !speech.speaking, !speech.listening else { return }
        let id = UUID(); requestID = id
        busy = true; error = ""; speech.stop()
        defer { if requestID == id { busy = false } }
        do {
            guard await LampAI.isAvailable(.text) else { error = "Your Italian coach needs AI connected in Lamp."; return }
            guard requestID == id else { return }
            if !start { turns.append(ConversationTurn(who: "You", text: input)); input = "" }
            let context = "Milestone: \(WeddingCoach.milestones[min(coach.selected, 2)]). Coach confidence: \(coach.state.scores[coach.selected] ?? 0)/5. Mother: \(coach.state.mother). Sister: \(coach.state.sister). Conversation: \(turns.map { $0.who + ": " + $0.text }.joined(separator: "\n"))"
            let result = try await LampAI.ask("Play a fictional warm Italian-speaking mother of Marco at his wedding rehearsal dinner. Family from Naples; use natural standard Italian, no stereotypes or invented personal facts. Speak only Italian in character, short beginner-accessible turns, one question each. Adapt to demonstrated ability and current milestone; gradually reduce scaffolding. If starting, greet the user. Otherwise gently explain one useful correction in English and offer a usable Italian alternative; distinguish transcription uncertainty from language errors. Score this reply’s functional readiness 1–5 (not a completed milestone). Return JSON {italian:String, translation:String, coaching:String, score:Int, phrase:String, meaning:String}. On opening, coaching is a short encouraging English hint. phrase is a useful short Italian phrase for today and meaning its English meaning.", data: context, as: RoleReply.self)
            guard requestID == id else { return }
            turns.append(ConversationTurn(who: coach.state.mother, text: result.italian))
            translation = result.translation; feedback = result.coaching
            coach.state.phrase = result.phrase; coach.state.meaning = result.meaning
            if !start { coach.record(coach.selected, score: result.score) } else { coach.save() }
            LampStore.save(turns, to: "conversation-\(coach.selected)")
            speech.say(result.italian)
        } catch { if requestID == id { self.error = error.localizedDescription } }
    }
}
