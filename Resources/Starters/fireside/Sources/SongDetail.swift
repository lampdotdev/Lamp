import SwiftUI

struct SongDetail: View {
    @EnvironmentObject var library:Library
    let song:Song
    let practice:(Bool)->Void
    let close:()->Void
    @State private var edit = false
    var missing: [String] { library.missing(song) }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:34) {
                hero
                chords
                HStack(alignment:.top,spacing:18) {
                    fact("TUNING",song.tuning,"tuningfork")
                    fact("HOW TO PLAY IT",song.pattern,"hand.draw")
                    fact("DIFFICULTY",song.difficulty,"chart.bar")
                }
                arrangement
                if !song.notes.isEmpty {
                    HStack(alignment:.top,spacing:12) {
                        Rectangle().fill(Color.rust.opacity(0.5)).frame(width:2)
                        Text(song.notes).font(.book(14)).italic().foregroundStyle(Color.pencil).textSelection(.enabled)
                    }
                }
                Text("Memory badges come from a full performance with the tab hidden. Chord matching is an estimate, not an exam board.")
                    .font(.caption).foregroundStyle(Color.pencil)
            }
            .padding(.horizontal,48).padding(.vertical,34).frame(maxWidth:1000).frame(maxWidth:.infinity)
        }
        .background(PaperBackground(coffeeRing:false))
        .toolbar {
            ToolbarItem(placement:.navigation) {
                Button(action:close) { Label("Back to Folder",systemImage:"chevron.backward") }.help("Back to the folder").keyboardShortcut("[",modifiers:.command)
            }
        }
        .sheet(isPresented:$edit) { ArrangementSheet(song:song) }
    }

    var hero: some View {
        HStack(alignment:.center,spacing:34) {
            ZStack {
                RoundedRectangle(cornerRadius:8).fill(Color.paperCard)
                    .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Color.ink.opacity(0.08)))
                    .shadow(color:.black.opacity(0.12),radius:10,y:5)
                RadialGradient(colors:[Color.mustard.opacity(0.25),.clear],center:.center,startRadius:10,endRadius:120).clipShape(RoundedRectangle(cornerRadius:8))
                SongArt.image(SongArt.file(for:song)).resizable().scaledToFit().padding(24)
            }
            .frame(width:220,height:220)
            .overlay(alignment:.top) { TapeStrip(angle:-4).offset(y:-10) }
            .rotationEffect(.degrees(-2.5))
            VStack(alignment:.leading,spacing:12) {
                Text(song.artist.uppercased()).font(.caption.weight(.semibold)).tracking(2.5).foregroundStyle(Color.rust)
                Text(song.title).font(.book(44,.medium)).foregroundStyle(Color.ink).fixedSize(horizontal:false,vertical:true)
                Journey(state:song.state)
                HStack(spacing:10) {
                    Button { practice(false) } label: { Label("Wait for Me",systemImage:"ear").padding(.horizontal,6).padding(.vertical,3) }
                        .buttonStyle(.borderedProminent).tint(.rust).controlSize(.large).disabled(song.sequence.isEmpty)
                        .help("Shows each chord and waits until it hears it")
                    Button { practice(true) } label: { Label("Play from Memory",systemImage:"eye.slash").padding(.horizontal,4).padding(.vertical,3) }
                        .controlSize(.large).disabled(song.state == "reading it" || song.sequence.isEmpty)
                        .help(song.state == "reading it" ? "Play it through once first" : "Hides the tab and listens to the whole song")
                    Menu {
                        if song.state == "reading it" { Button("I Can Play It") { var s = song; s.state = "can play it"; library.save(s) } }
                        Button("Edit Arrangement…") { edit = true }
                    } label: { Image(systemName:"ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().help("More")
                }.padding(.top,6)
            }
            Spacer(minLength:0)
        }
    }

    var chords: some View {
        VStack(alignment:.leading,spacing:14) {
            sectionTitle("THE CHORDS",missing.isEmpty ? "all of them already yours" : "\(missing.count) new to learn")
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:16) {
                    ForEach(song.chords,id:\.self) { chord in
                        let isNew = missing.contains(chord)
                        VStack(spacing:8) {
                            ChordDiagram(chord:chord,width:66,highlight:isNew ? .rust : .ink)
                            if isNew { Stamp(text:"New",color:.rust,angle:-5,size:8) } else { Text("in hand").font(.system(size:10,design:.serif)).italic().foregroundStyle(Color.sage) }
                        }
                        .padding(14)
                        .background(Color.paperCard,in:RoundedRectangle(cornerRadius:8))
                        .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(isNew ? Color.rust.opacity(0.5) : Color.ink.opacity(0.08),style:StrokeStyle(lineWidth:1,dash:isNew ? [4,3] : [])))
                    }
                }.padding(2)
            }
        }
    }

    var arrangement: some View {
        VStack(alignment:.leading,spacing:14) {
            sectionTitle("THE ARRANGEMENT","one chord per bar, \(song.sequence.count) bars")
            if song.sequence.isEmpty {
                Text("Add a complete chord sequence before listening can follow this song.").font(.book(14)).italic().foregroundStyle(Color.pencil)
                Button("Edit Arrangement…") { edit = true }
            } else {
                let rows = stride(from:0,to:song.sequence.count,by:4).map { Array(song.sequence[$0..<min($0+4,song.sequence.count)]) }
                VStack(spacing:0) {
                    ForEach(Array(rows.enumerated()),id:\.offset) { r,row in
                        HStack(spacing:0) {
                            ForEach(Array(row.enumerated()),id:\.offset) { i,chord in
                                BarLine(heavy: r == 0 && i == 0)
                                VStack(alignment:.leading,spacing:2) {
                                    Text("\(r*4+i+1)").font(.system(size:9,weight:.medium)).monospacedDigit().foregroundStyle(Color.pencil.opacity(0.7))
                                    Text(chord).font(.book(24,.semibold)).foregroundStyle(missing.contains(chord) ? Color.rust : Color.ink)
                                }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,14).padding(.vertical,10)
                            }
                            if row.count < 4 { ForEach(0..<(4-row.count),id:\.self) { _ in Color.clear.frame(maxWidth:.infinity) } }
                            BarLine(heavy: r == rows.count-1)
                        }
                        .overlay(alignment:.bottom) { Rectangle().fill(Color.pencil.opacity(0.18)).frame(height:1) }
                    }
                }
                .padding(.vertical,6)
                .background(Color.paperCard.opacity(0.7),in:RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Color.ink.opacity(0.07)))
            }
        }
    }

    func sectionTitle(_ title:String,_ aside:String) -> some View {
        HStack(alignment:.firstTextBaseline,spacing:10) {
            Text(title).font(.caption.weight(.bold)).tracking(2.5).foregroundStyle(Color.ink)
            Text(aside).font(.book(13)).italic().foregroundStyle(Color.pencil)
            Rectangle().fill(Color.pencil.opacity(0.25)).frame(height:1)
        }
    }
    func fact(_ title:String,_ value:String,_ symbol:String) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Label(title,systemImage:symbol).font(.caption2.weight(.bold)).tracking(2).foregroundStyle(Color.rust)
            Text(value.isEmpty ? "Not written down" : value).font(.book(15)).foregroundStyle(Color.ink).fixedSize(horizontal:false,vertical:true)
        }
        .padding(16).frame(maxWidth:.infinity,minHeight:96,alignment:.topLeading)
        .background(Color.paperCard,in:RoundedRectangle(cornerRadius:8))
        .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Color.ink.opacity(0.08)))
    }
}

struct BarLine: View {
    let heavy: Bool
    var body: some View { Rectangle().fill(Color.ink.opacity(heavy ? 0.7 : 0.35)).frame(width:heavy ? 2.5 : 1).padding(.vertical,8) }
}

/// Reading it → can play it → by heart, as stops on a road.
struct Journey: View {
    let state: String
    let stops = ["reading it","can play it","know it by heart"]
    var body: some View {
        let at = stops.firstIndex(of:state) ?? 0
        HStack(spacing:0) {
            ForEach(stops.indices,id:\.self) { i in
                HStack(spacing:6) {
                    ZStack {
                        Circle().fill(i <= at ? Color.rust : Color.clear).frame(width:12,height:12)
                        Circle().strokeBorder(i <= at ? Color.rust : Color.pencil.opacity(0.5),lineWidth:1.5).frame(width:12,height:12)
                        if i < at { Image(systemName:"checkmark").font(.system(size:7,weight:.black)).foregroundStyle(.white) }
                    }
                    Text(i == 2 ? "by heart" : stops[i]).font(.book(13,i == at ? .semibold : .regular)).italic(i != at).foregroundStyle(i <= at ? Color.ink : Color.pencil)
                }
                if i < 2 {
                    Rectangle().fill(i < at ? Color.rust : Color.pencil.opacity(0.3)).frame(width:36,height:1.5).padding(.horizontal,8)
                }
            }
        }
        .accessibilityElement().accessibilityLabel("Progress: \(state)")
    }
}
