import SwiftUI

struct ContentView: View {
    @EnvironmentObject var coach: WeddingCoach
    @SceneStorage("page") private var page = "home"
    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Label("The wedding", systemImage: "heart").tag("home")
                Label("At the table", systemImage: "fork.knife").tag("practice")
                Label("My toast", systemImage: "wineglass").tag("toast")
            }.navigationTitle("Wedding Words")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Italian for one wedding").font(Look.script(19)).foregroundStyle(Look.ink).fixedSize(horizontal: false, vertical: true)
                    Text("Rehearse family conversations with an AI coach. Write your toast, practice it aloud, and build confidence before the big day.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
            }.frame(maxWidth: .infinity, maxHeight: .infinity).pageBackground()
            .toolbarBackground(Look.paper, for: .windowToolbar)
        }.tint(Look.ink).frame(minWidth: 960, minHeight: 720)
    }
    var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                invitation
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Can I do it yet?").font(Look.serif(24))
                        Text("Rehearsals, not lessons. Confidence comes from trying out loud.").foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { index in
                            if index > 0 { Divider().padding(.leading, 70) }
                            milestone(index)
                        }
                    }.invitationCard(padding: 6)
                }
                LemonRule().padding(.horizontal, 60)
                phrase
            }.padding(30).frame(maxWidth: 950)
        }.navigationTitle("The wedding")
    }
    /// The countdown, set like a save-the-date card under a lemon branch.
    var invitation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("save the date").font(Look.script(46)).foregroundStyle(Look.ink).padding(.bottom, -4)
            VStack(alignment: .leading, spacing: 6) {
                Engraved("\(coach.state.sister) & Marco")
                Engraved("are getting married")
            }
            Text("You have \(coach.days) days.").font(Look.serif(44)).padding(.top, 14)
            Text("To make her feel like family. And make 120 people cry.\nThe good kind.").font(.title3).foregroundStyle(.secondary)
            Engraved(coach.state.wedding.formatted(date: .long, time: .omitted), size: 12).padding(.top, 10)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .invitationCard(padding: 24, radius: 18)
        .overlay(alignment: .topTrailing) {
            // Half the card at most, so the words keep their side of it at any width.
            GeometryReader { card in
                LemonBranch().frame(width: min(card.size.width * 0.52, 470)).frame(maxWidth: .infinity, alignment: .trailing)
            }.clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .accessibilityElement(children: .combine)
    }
    func milestone(_ index: Int) -> some View {
        Button {
            coach.selected = index; page = index == 3 ? "toast" : "practice"
        } label: {
            HStack(spacing: 16) {
                Image(systemName: ["hand.wave", "fork.knife", "heart", "wineglass"][index])
                    .font(.title3).foregroundStyle(Look.ink)
                    .frame(width: 38, height: 38)
                    .background(Look.wash, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(WeddingCoach.milestones[index]).font(.headline)
                    Text(coach.status(index)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                LemonScore(score: coach.state.scores[index])
                Text("Rehearse").foregroundStyle(Look.ink).padding(.leading, 14)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    /// Today's phrase, beside a maiolica tile.
    var phrase: some View {
        HStack(alignment: .top, spacing: 22) {
            MaiolicaTile().frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 8) {
                Engraved("Today’s tiny act of bravery")
                Text(coach.state.phrase).font(Look.serif(26, italic: true)).textSelection(.enabled)
                Text(coach.state.meaning).foregroundStyle(.secondary)
                HStack {
                    Button("Hear it", systemImage: "speaker.wave.2") { coach.speech.say(coach.state.phrase) }
                    Button("Practice my weakest milestone") { coach.selected = coach.weakest; page = coach.selected == 3 ? "toast" : "practice" }
                }.padding(.top, 4)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).invitationCard(padding: 22)
    }
}
