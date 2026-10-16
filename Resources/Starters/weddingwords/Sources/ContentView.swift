import SwiftUI

struct ContentView: View {
    @EnvironmentObject var coach: WeddingCoach
    @SceneStorage("page") private var page = "home"
    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Label("The wedding", systemImage: "heart").tag("home")
                Label("At the table", systemImage: "bubble.left.and.bubble.right").tag("practice")
                Label("My toast", systemImage: "wineglass").tag("toast")
            }.navigationTitle("Wedding Words")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Italian for one wedding").font(.caption.weight(.semibold))
                    Text("Rehearse family conversations with an AI coach. Write your toast, practice it aloud, and build confidence before the big day.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            Group {
                switch page {
                case "practice": PracticeView()
                case "toast": ToastView()
                default: home
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.tint(.terracotta).frame(minWidth: 960, minHeight: 720)
    }
    var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ONE WEDDING. YOUR WORDS.").font(.caption.weight(.semibold)).tracking(2)
                    Text("You have \(coach.days) days.").font(.system(size: 46, weight: .medium, design: .serif))
                    Text("To make her feel like family. And make 120 people cry.\nThe good kind.").font(.title3).foregroundStyle(.secondary)
                    Label(coach.state.wedding.formatted(date: .long, time: .omitted), systemImage: "calendar").font(.callout)
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(Color.terracotta.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                Text("Can I do it yet?").font(.title2.bold())
                Text("Rehearsals, not lessons. Confidence comes from trying out loud.").foregroundStyle(.secondary)
                ForEach(0..<4, id: \.self) { index in
                    Button {
                        coach.selected = index; page = index == 3 ? "toast" : "practice"
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: ["hand.wave", "fork.knife", "heart", "wineglass"][index]).font(.title2).frame(width: 36)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(WeddingCoach.milestones[index]).font(.headline)
                                Text(coach.status(index)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Text("Rehearse"); Image(systemName: "chevron.right").font(.caption)
                        }.padding(17).background(.background, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label("Today’s tiny act of bravery", systemImage: "sun.max").font(.headline)
                    Text(coach.state.phrase).font(.title3)
                    Text(coach.state.meaning).foregroundStyle(.secondary)
                    HStack {
                        Button("Hear it", systemImage: "speaker.wave.2") { coach.speech.say(coach.state.phrase) }
                        Button("Practice my weakest milestone") { coach.selected = coach.weakest; page = coach.selected == 3 ? "toast" : "practice" }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.terracotta.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }.padding(30).frame(maxWidth: 950)
        }.navigationTitle("The wedding")
    }
}
extension Color { static let terracotta = Color(red: 0.67, green: 0.29, blue: 0.21) }
