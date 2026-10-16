import SwiftUI

struct PracticeView: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) var dismiss
    let song: Song
    let memory: Bool
    @StateObject private var listener = GuitarListener()
    @State private var index = 0
    @State private var finished = false
    @State private var started = false
    @State private var chorusRuns = 0
    @State private var showBridge = false
    @State private var loopChorus = false
    @State private var firstBar = 1
    @State private var lastBar = 1
    @State private var glow = false

    var current: String { song.sequence.isEmpty ? "—" : song.sequence[min(index,song.sequence.count-1)] }
    var mood: Color { listener.quality == 2 ? .green : listener.quality == 1 ? .orange : Color(red:1,green:0.62,blue:0.3) }

    var body: some View {
        ZStack {
            stage
            VStack(spacing:0) {
                topBar
                Spacer(minLength:10)
                if finished { finale } else if memory { memoryCenter } else { followCenter }
                Spacer(minLength:10)
                if !finished { bottom }
            }.padding(28)
        }
        .frame(width:720,height:640)
        .environment(\.colorScheme,.dark)
        .onDisappear { listener.stop() }
        .onAppear { lastBar = song.sequence.count; withAnimation(.easeInOut(duration:2.4).repeatForever()) { glow = true } }
    }

    // A dark room lit from below by the fire.
    var stage: some View {
        ZStack {
            Color(red:0.075,green:0.055,blue:0.045)
            RadialGradient(colors:[mood.opacity(glow ? 0.34 : 0.24),.clear],center:UnitPoint(x:0.5,y:0.55),startRadius:20,endRadius:glow ? 380 : 330)
                .animation(.easeInOut(duration:0.5),value:listener.quality)
            LinearGradient(colors:[.clear,Color(red:0.4,green:0.15,blue:0.05).opacity(0.35)],startPoint:.center,endPoint:.bottom)
            Embers()
        }.ignoresSafeArea()
    }

    var topBar: some View {
        HStack(alignment:.firstTextBaseline) {
            VStack(alignment:.leading,spacing:3) {
                Text(memory ? "FROM MEMORY" : "WAIT FOR ME").font(.caption2.weight(.bold)).tracking(3).foregroundStyle(Color(red:1,green:0.65,blue:0.35))
                Text(song.title).font(.book(20,.medium)).foregroundStyle(.white.opacity(0.92)).lineLimit(1)
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    var followCenter: some View {
        VStack(spacing:22) {
            HStack(alignment:.center,spacing:40) {
                ZStack {
                    Circle().strokeBorder(mood.opacity(0.65),lineWidth:3).frame(width:230,height:230)
                        .shadow(color:mood.opacity(0.7),radius:listener.quality > 0 ? 24 : 8)
                        .scaleEffect(listener.quality == 2 ? 1.06 : 1)
                    Circle().trim(from:0,to:max(0.001,listener.inputLevel)).stroke(mood.opacity(0.4),style:StrokeStyle(lineWidth:6,lineCap:.round)).rotationEffect(.degrees(-90)).frame(width:252,height:252).opacity(listener.inputLevel > 0.02 ? 1 : 0)
                        .animation(.linear(duration:0.08),value:listener.inputLevel)
                    Text(current).font(.system(size:96,weight:.semibold,design:.serif)).foregroundStyle(listener.quality == 2 ? .green : .white)
                        .contentTransition(.numericText()).id(index)
                        .transition(.asymmetric(insertion:.scale(scale:0.6).combined(with:.opacity),removal:.move(edge:.leading).combined(with:.opacity)))
                }
                .animation(.spring(response:0.4,dampingFraction:0.6),value:index)
                .animation(.spring(response:0.3,dampingFraction:0.5),value:listener.quality)
                ChordDiagram(chord:current,width:96,highlight:mood,showName:false)
                    .padding(18).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
            }
            ticker
            Text(listener.feedback).font(.book(17)).italic().foregroundStyle(listener.quality == 2 ? .green : listener.quality == 1 ? .orange : .white.opacity(0.75))
                .multilineTextAlignment(.center).frame(height:44).animation(.easeInOut,value:listener.feedback)
        }
    }

    // What came before, dimmed; what comes next, waiting.
    var ticker: some View {
        HStack(spacing:10) {
            ForEach(max(0,index-2)..<min(song.sequence.count,index+6),id:\.self) { i in
                Text(song.sequence[i]).font(.book(i == index ? 22 : 17,i == index ? .bold : .regular))
                    .foregroundStyle(i < index ? .white.opacity(0.28) : i == index ? mood : .white.opacity(0.7))
                    .strikethrough(i < index,color:.white.opacity(0.25))
                    .frame(minWidth:44).padding(.vertical,6)
                    .background(i == index ? mood.opacity(0.15) : .clear,in:Capsule())
            }
        }
        .animation(.spring(response:0.4),value:index)
        .accessibilityElement().accessibilityLabel(index+1 < song.sequence.count ? "Next: \(song.sequence[index+1])" : "Last chord")
    }

    var memoryCenter: some View {
        VStack(spacing:20) {
            SongArt.image("lantern.png").resizable().scaledToFit().frame(height:220)
                .shadow(color:Color(red:1,green:0.75,blue:0.3).opacity(0.35+listener.inputLevel*0.6),radius:30+listener.inputLevel*40)
                .scaleEffect(1+listener.inputLevel*0.04)
                .animation(.easeOut(duration:0.12),value:listener.inputLevel)
            Text("The tab is tucked away.").font(.book(26,.medium)).foregroundStyle(.white)
            Text(listener.quality == 2 ? "Sounding good. Keep going." : "Play the whole thing through. Take your time.").font(.book(16)).italic().foregroundStyle(.white.opacity(0.7))
        }
    }

    var finale: some View {
        VStack(spacing:18) {
            SongArt.image("campfire.png").resizable().scaledToFit().frame(height:200)
                .shadow(color:.orange.opacity(0.7),radius:40)
                .transition(.scale(scale:0.3).combined(with:.opacity))
            if memory { Stamp(text:"By heart",color:Color(red:1,green:0.5,blue:0.3),angle:-8,size:22) }
            Text(memory ? "One more for the campfire." : "Nicely played. No metronome was harmed.").font(.book(28,.medium)).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(memory ? "\(library.memorized) of 20 songs now live in your hands, not on paper." : "That counts as ‘can play it’. Next time, try it from memory.").font(.book(15)).italic().foregroundStyle(.white.opacity(0.7))
            Button("Back to the Songbook") { dismiss() }.buttonStyle(.borderedProminent).tint(.rust).controlSize(.large).padding(.top,6)
        }
    }

    var bottom: some View {
        VStack(spacing:14) {
            // One segment per bar, lit as you go.
            HStack(spacing:2) {
                ForEach(0..<max(1,song.sequence.count),id:\.self) { i in
                    Capsule().fill(i < index ? Color.orange : i == index && !memory ? Color.orange.opacity(0.5) : .white.opacity(memory ? 0.08 : 0.14)).frame(height:5)
                }
            }.animation(.easeOut,value:index)
            HStack {
                Text(memory ? "\(index) bars played" : "Bar \(min(index+1,song.sequence.count)) of \(song.sequence.count)").font(.caption).monospacedDigit().foregroundStyle(.white.opacity(0.6))
                Spacer()
                if listener.running && !memory && !listener.heard.isEmpty { Text("Hearing \(listener.heard)").font(.caption).foregroundStyle(.white.opacity(0.6)) }
            }
            if let error = listener.error { Text(error).foregroundStyle(.red).font(.callout) }
            if showBridge { Text("Four runs through. Ready for the bridge?").font(.book(15)).italic().foregroundStyle(.orange) }
            if !started {
                HStack(spacing:16) {
                    if !memory && !song.sequence.isEmpty {
                        Toggle("Loop a section",isOn:$loopChorus).toggleStyle(.switch).controlSize(.small)
                        if loopChorus {
                            Stepper("From bar \(firstBar)",value:$firstBar,in:1...max(1,song.sequence.count)).fixedSize()
                            Stepper("to \(lastBar)",value:$lastBar,in:firstBar...max(firstBar,song.sequence.count)).fixedSize()
                        }
                    }
                    Spacer()
                    Button { start() } label: { Label("Start Listening",systemImage:"waveform").padding(.horizontal,8).padding(.vertical,3) }
                        .buttonStyle(.borderedProminent).tint(.rust).controlSize(.large).keyboardShortcut(.defaultAction).disabled(song.sequence.isEmpty)
                }
            } else if !listener.running && listener.error == nil {
                ProgressView("Opening audio input…").controlSize(.small)
            } else if listener.error != nil {
                Button("Try Listening Again") { Task { await listener.start() } }
            }
            Text("Listens through your Mac’s selected input. Feedback is approximate and forgiving in a noisy room.")
                .font(.caption2).foregroundStyle(.white.opacity(0.4))
        }
    }

    func start() {
        guard !song.sequence.isEmpty else { return }
        started = true; index = loopChorus && !memory ? firstBar-1 : 0; listener.target = song.sequence[index]
        listener.onChord = {
            index += 1
            if loopChorus && !memory && index >= max(firstBar,lastBar) {
                chorusRuns += 1; index = firstBar-1
                if chorusRuns == 4 {
                    showBridge = true
                    if library.nudges { LampNotifications.send("The chorus knows you now",body:"You’ve run this chorus four times. Ready for the bridge?") }
                }
                listener.target = song.sequence[index]
                return
            }
            if index >= song.sequence.count {
                listener.stop()
                withAnimation(.spring(response:0.6,dampingFraction:0.6)) { finished = true }
                var updated = library.songs.first {$0.id == song.id} ?? song
                if memory { updated.state = "know it by heart"; updated.learned = Date() }
                else if updated.state != "know it by heart" { updated.state = "can play it" }
                library.save(updated); library.record(updated,completed:true)
            } else { listener.target = song.sequence[index] }
        }
        library.record(song,completed:false)
        Task { await listener.start() }
    }
}

/// Sparks drifting up from the fire.
struct Embers: View {
    var body: some View {
        TimelineView(.animation(minimumInterval:1/30)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<26 {
                    let seed = Double(stableHash("ember\(i)") % 1000) / 1000
                    let speed = 18 + seed * 30
                    let life = size.height + 40
                    let y = size.height + 20 - (t * speed + seed * life).truncatingRemainder(dividingBy:life)
                    let x = size.width * (0.15 + seed * 0.7) + sin(t * (0.6 + seed) + seed * 9) * 22
                    let fade = max(0,min(1,(y / size.height)))
                    let r = 1 + seed * 1.8
                    ctx.fill(Path(ellipseIn:CGRect(x:x,y:y,width:r,height:r)),with:.color(Color(red:1,green:0.55+seed*0.3,blue:0.2).opacity(0.65*fade)))
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
