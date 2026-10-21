import SwiftUI

struct ToastLine: Codable, Identifiable {
    var id: String { italian }
    let italian: String
    let english: String
    let pronunciation: String
}
struct ToastResult: Decodable { let lines: [ToastLine] }
struct ToastFeedback: Decodable { let coaching: String; let score: Int }
struct ToastView: View {
    @EnvironmentObject var coach: WeddingCoach
    @State private var busy = false
    @State private var error = ""
    @State private var feedback = ""
    @State private var input = ""
    @State private var line = 0
    @State private var full = false
    @State private var confirmRebuild = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(script: "il brindisi", title: "For your sister. In your own Italian.", subtitle: "120 guests don’t need perfect Italian. They need to hear you mean it.")
                VStack(alignment: .leading, spacing: 10) {
                    Engraved("Start with the things only you could say").padding(.bottom, 4)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your rough English toast").font(.headline)
                        TextEditor(text: $coach.state.draft).font(.body).scrollContentBackground(.hidden).padding(6).frame(height: 100).background(Look.paper, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("Rough English toast")
                        Text("A few stories about your sister").font(.headline)
                        TextEditor(text: $coach.state.stories).font(.body).scrollContentBackground(.hidden).padding(6).frame(height: 80).background(Look.paper, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("Stories about your sister")
                        Text("A childhood moment, why Marco is her person, something that still makes you laugh. Real stories only.").font(.caption).foregroundStyle(.secondary)
                        Button(coach.state.lines.isEmpty ? "Find my Italian words" : "Rebuild for my Italian now", systemImage: "sparkles") {
                            if coach.state.lines.isEmpty { Task { await build() } } else { confirmRebuild = true }
                        }.disabled(busy || (coach.state.draft.isEmpty && coach.state.stories.isEmpty)).buttonStyle(.borderedProminent)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).invitationCard(padding: 22)
                if !coach.state.lines.isEmpty {
                    HStack {
                        Text("Make it yours, one breath at a time").font(Look.serif(22))
                        Spacer()
                        Toggle("Full run-through", isOn: $full).toggleStyle(.switch)
                    }
                    if full {
                        // The whole toast, set like the card it will be read from.
                        VStack(spacing: 14) {
                            Text("Alla sposa e allo sposo").font(Look.script(30)).foregroundStyle(Look.ink)
                            ForEach(coach.state.lines) { item in Text(item.italian).font(Look.serif(21)).multilineTextAlignment(.center).textSelection(.enabled) }
                            LemonRule().frame(width: 180).padding(.vertical, 4)
                            Button("Hear the whole toast", systemImage: "speaker.wave.2") { coach.speech.say(coach.state.lines.map(\.italian).joined(separator: "\n"), slow: true) }
                        }.padding(.vertical, 16).frame(maxWidth: .infinity).invitationCard(padding: 24, radius: 18)
                    } else {
                        let item = coach.state.lines[min(line, coach.state.lines.count - 1)]
                        VStack(alignment: .leading, spacing: 10) {
                            Engraved("Line \(line + 1) of \(coach.state.lines.count)")
                            Text(item.italian).font(Look.serif(30, italic: true)).textSelection(.enabled)
                            Text(item.english).foregroundStyle(.secondary)
                            Label(item.pronunciation, systemImage: "mouth").font(.callout).foregroundStyle(Look.ink)
                            HStack {
                                Button("Previous", systemImage: "chevron.left") { line = max(0, line - 1); feedback = "" }.disabled(line == 0)
                                Button("Hear slowly", systemImage: "speaker.wave.2") { coach.speech.say(item.italian, slow: true) }
                                Button("Next", systemImage: "chevron.right") { line = min(coach.state.lines.count - 1, line + 1); feedback = "" }.disabled(line == coach.state.lines.count - 1)
                            }.padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 110)
                        .overlay(alignment: .topTrailing) { LemonMark(filled: true).frame(width: 54, height: 38).rotationEffect(.degrees(-12)) }
                        .invitationCard(padding: 24, radius: 18)
                    }
                    SpeakingInput(speech: coach.speech, text: $input)
                    Button(full ? "Coach my full run-through" : "Coach this line", systemImage: "heart.text.clipboard") { Task { await assess() } }.disabled(busy || input.isEmpty)
                    Text("Your coach checks the words recognized from your voice. The slow Italian model and sound guide help pronunciation; recognition can miss accents.").font(.caption).foregroundStyle(.secondary)
                    if !feedback.isEmpty { Label(feedback, systemImage: "heart.text.clipboard").frame(maxWidth: .infinity, alignment: .leading).invitationCard(padding: 14, radius: 12) }
                }
                if busy { ProgressView("Finding words that sound like you…") }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }.padding(28)
        }.navigationTitle("My toast")
        .onChange(of: coach.state.draft) { _, _ in coach.save() }
        .onChange(of: coach.state.stories) { _, _ in coach.save() }
        .confirmationDialog("Replace your current Italian toast? Your English draft and stories stay.", isPresented: $confirmRebuild) {
            Button("Rebuild toast") { Task { await build() } }
        }
    }
    @MainActor func build() async {
        busy = true; error = ""; defer { busy = false }
        do {
            guard await LampAI.isAvailable(.text) else { error = "Connect AI in Lamp to write with your Italian coach."; return }
            let result = try await LampAI.ask("Write a short heartfelt Italian wedding toast from a sibling to their sister and Marco, for 120 guests including his Italian-speaking mother from Naples. Use only supplied facts and stories; invent none. Preserve the speaker’s voice, light gentle humor, no stereotypes. Adapt complexity to demonstrated scores (1 beginner to 5 confident); beginner by default. Short speakable lines, 60–90 seconds total. Return JSON {lines:[{italian:String,english:String,pronunciation:String}]}. Pronunciation is a practical English-speaker syllable guide with stressed syllables capitalized. Rebuild the previous version at current ability, retaining meaning.", data: "Sister: \(coach.state.sister)\nDraft: \(coach.state.draft)\nStories: \(coach.state.stories)\nScores: \(coach.state.scores)\nPrevious: \(coach.state.lines.map(\.italian).joined(separator: "\n"))", as: ToastResult.self)
            guard !result.lines.isEmpty else { error = "No toast came back. Try again."; return }
            coach.state.lines = result.lines; coach.save(); line = 0
        } catch { self.error = error.localizedDescription }
    }
    @MainActor func assess() async {
        busy = true; error = ""; coach.speech.stop(); defer { busy = false }
        // The toggle can change while the coach answers: the answer belongs to what was submitted.
        let full = self.full
        do {
            guard await LampAI.isAvailable(.text) else { error = "Connect AI in Lamp to rehearse with your coach."; return }
            let target = full ? coach.state.lines.map(\.italian).joined(separator: "\n") : coach.state.lines[min(line, coach.state.lines.count - 1)].italian
            let result = try await LampAI.ask("Gently coach a learner rehearsing a wedding toast in Italian. Compare recognized speech to target. Give one concrete correction and a short retry instruction, warmly in English. Do not claim to hear audio or judge accent from text; allow transcription uncertainty. Return JSON {coaching:String,score:Int} with functional readiness 1–5.", data: "Target: \(target)\nRecognized or typed: \(input)", as: ToastFeedback.self)
            feedback = result.coaching
            if full { coach.record(3, score: result.score) } else { coach.state.lastPractice = Date(); coach.save(); coach.scheduleNotifications() }
        } catch { self.error = error.localizedDescription }
    }
}
