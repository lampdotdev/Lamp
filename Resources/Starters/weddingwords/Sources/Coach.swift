import SwiftUI

struct WeddingState: Codable {
    // Three months from the first launch, so the countdown means something whenever Lamp was installed.
    var wedding = Calendar.current.date(byAdding: .month, value: 3, to: Calendar.current.startOfDay(for: Date()))!
    var sister = "my sister"
    var mother = "Marco’s mother"
    var draft = ""
    var stories = ""
    var lines: [ToastLine] = []
    var scores: [Int: Int] = [:]
    var attempts: [Int: Int] = [:]
    var lastPractice: Date? = nil
    var reminders = false
    var hour = 18
    var phrase = "È un piacere conoscerla!"
    var meaning = "It’s a pleasure to meet you! Polite, warm, and a very good start."
}
@MainActor final class WeddingCoach: ObservableObject {
    static let milestones = ["Introduce myself to Marco’s mother", "Handle small talk at the table", "Politely survive a third plate", "Deliver the toast"]
    @Published var state: WeddingState
    @Published var selected = 0
    let speech = WeddingSpeech()
    private var daily: LampSchedule?
    init() {
        if let saved = LampStore.load(WeddingState.self, from: "wedding") {
            state = saved
        } else {
            // Kept at once, so the date picked on the first launch stays the wedding's.
            state = WeddingState(); LampStore.save(state, to: "wedding")
        }
        daily = LampSchedule.daily("wedding-coach", hour: 9) { [weak self] in await self?.dailyCoaching() }
    }
    func dailyCoaching() async {
        guard state.reminders, days > 0 else { return }
        struct Phrase: Decodable { let italian: String; let meaning: String }
        do {
            guard await LampAI.isAvailable(.text) else { scheduleNotifications(); return }
            let phrase = try await LampAI.ask("Choose a fresh short beginner Italian phrase to rehearse for a sister’s wedding to Marco. Return JSON {italian:String,meaning:String}. Focus on the weakest milestone in the supplied data. Friendly English meaning, natural standard Italian, no stereotypes.", data: "Weakest: \(Self.milestones[weakest]). Previous phrase: \(state.phrase). Scores: \(state.scores)", as: Phrase.self)
            state.phrase = phrase.italian; state.meaning = phrase.meaning; save()
        } catch { print("Daily wedding coaching: \(error.localizedDescription)") }
        scheduleNotifications()
    }
    var days: Int { max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: state.wedding)).day ?? 0) }
    var weakest: Int { (0..<4).min { (state.scores[$0] ?? 0) < (state.scores[$1] ?? 0) } ?? 0 }
    func status(_ i: Int) -> String {
        // The coach's confidence is the lemons beside it.
        guard state.scores[i] != nil else { return "Not rehearsed yet · let’s try it together" }
        let attempts = state.attempts[i] ?? 0
        return attempts == 1 ? "Rehearsed once" : "Rehearsed \(attempts) times"
    }
    func save() { LampStore.save(state, to: "wedding") }
    func record(_ i: Int, score: Int) {
        state.scores[i] = min(5, max(1, score)); state.attempts[i, default: 0] += 1
        state.lastPractice = Date(); save(); scheduleNotifications()
    }
    func scheduleNotifications() {
        for d in 0...60 { LampNotifications.cancel("wedding-\(d)") }
        guard state.reminders, days > 0 else { return }
        // Today's reminder too, while its hour is still ahead: a refresh mustn't skip it.
        for d in 0...min(days, 60) {
            let base = Calendar.current.date(byAdding: .day, value: d, to: Date())!
            let date = Calendar.current.date(bySettingHour: state.hour, minute: 0, second: 0, of: base)!
            let remaining = Calendar.current.dateComponents([.day], from: base, to: state.wedding).day ?? 0
            var body = "One phrase today: \(state.phrase) — \(state.meaning)"
            let last = state.lastPractice ?? Date()
            let quietDays = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last), to: Calendar.current.startOfDay(for: date)).day ?? 0
            if quietDays == 2 { body = "Two quiet days? Come back for one sentence. The pasta won’t judge. \(state.phrase)" }
            if remaining <= 21 && d % 2 == 0 { body = "120 guests. One proud sister. Stand up and rehearse your whole toast today." }
            guard date > Date() else { continue }
            LampNotifications.send("A little Italian for the wedding", body: body, at: date, id: "wedding-\(d)")
        }
    }
}
struct CoachSettings: View {
    @EnvironmentObject var coach: WeddingCoach
    var body: some View {
        Form {
            Section("This one wedding") {
                DatePicker("Wedding date", selection: $coach.state.wedding, displayedComponents: .date)
                TextField("Your sister’s name", text: $coach.state.sister)
                TextField("Marco’s mother’s name", text: $coach.state.mother)
            }
            Section("A coach, never a streak counter") {
                Toggle("Send daily coaching notifications", isOn: $coach.state.reminders)
                Stepper("Daily nudge at \(coach.state.hour):00", value: $coach.state.hour, in: 0...23)
                Text("A phrase each day, a return after two quiet days, and full toast rehearsals in the final three weeks. Planned ahead while this app is closed; refreshed whenever you rehearse.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 490)
        .onChange(of: coach.state.wedding) { _, _ in coach.save(); coach.scheduleNotifications() }
        .onChange(of: coach.state.sister) { _, _ in coach.save() }
        .onChange(of: coach.state.mother) { _, _ in coach.save() }
        .onChange(of: coach.state.reminders) { _, _ in coach.save(); coach.scheduleNotifications() }
        .onChange(of: coach.state.hour) { _, _ in coach.save(); coach.scheduleNotifications() }
    }
}
