import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: Library
    @SceneStorage("folder") private var folder = "camp"
    @SceneStorage("song") private var selection = ""
    @SceneStorage("query") private var query = ""
    @State private var addFolder = false
    @State private var addSong = false
    @State private var practice: PracticeChoice?
    @State private var deleting: Song?
    var currentFolder: SongFolder? { library.folders.first {$0.id == folder} }
    var filtered: [Song] {
        library.songs.filter { (folder == "all" || $0.folders.contains(folder)) && (query.isEmpty || ($0.title + $0.artist + $0.chords.joined()).localizedCaseInsensitiveContains(query)) }.sorted { ($0.ranks[folder] ?? 0) > ($1.ranks[folder] ?? 0) }
    }
    var body: some View {
        NavigationSplitView {
            Sidebar(folder:$folder)
                .navigationSplitViewColumnWidth(min:220,ideal:250,max:300)
        } detail: {
            if let song = library.songs.first(where:{$0.id == selection}) {
                SongDetail(song:song,practice:{ memory in practice = PracticeChoice(song:song,memory:memory) },close:{selection = ""})
            } else {
                home
            }
        }
        .searchable(text:$query,prompt:"Find a song or chord")
        .toolbar {
            ToolbarItemGroup {
                if library.busy { ProgressView().controlSize(.small).help("Reading the small print…") }
                Button { addFolder = true } label: { Label("New Folder",systemImage:"folder.badge.plus") }.help("Describe a new folder")
                Button { addSong = true } label: { Label("Add Song",systemImage:"plus") }.help("Add a tab or link").keyboardShortcut("i")
            }
        }
        .tint(.rust)
        .lampDropFiles { urls in Task { await library.receive(urls) } }
        .onOpenURL { url in Task {await library.receive([url])} }
        .lampSpotlightOpen { id in selection = id }
        .onChange(of:folder) { _,_ in selection = "" }
        .sheet(isPresented:$addFolder) { FolderSheet() }
        .sheet(isPresented:$addSong) { ImportSheet() }
        .sheet(item:$practice) { choice in PracticeView(song:choice.song,memory:choice.memory) }
        .alert("Songbook note",isPresented:Binding(get:{library.message != nil},set:{if !$0 {library.message = nil}})) { Button("OK") {library.message = nil} } message: {Text(library.message ?? "")}
        .confirmationDialog("Delete this song?",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting = nil}}),titleVisibility:.visible) {
            Button("Delete song",role:.destructive) { if let song = deleting { library.songStore.delete(song.id); library.songs.removeAll {$0.id == song.id}; LampSpotlight.remove(song.id) }; deleting = nil }
        }
        .frame(minWidth:980,minHeight:680)
    }

    var home: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:30) {
                header
                HStack(alignment:.top,spacing:18) {
                    PlayableTicket(count:library.playable,total:library.songs.count,byHeart:library.memorized)
                    UnlockTicket(chord:library.unlock.0,count:library.unlock.1)
                }
                if filtered.isEmpty {
                    emptyState
                } else {
                    HStack(alignment:.firstTextBaseline) {
                        Text(folder == "all" ? "EVERY SONG" : "IN THIS FOLDER, BEST FIRST").font(.caption.weight(.semibold)).tracking(2.5).foregroundStyle(Color.pencil)
                        Rectangle().fill(Color.pencil.opacity(0.25)).frame(height:1)
                        Text("\(filtered.count) \(filtered.count == 1 ? "song" : "songs")").font(.book(13)).italic().foregroundStyle(Color.pencil)
                    }
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:220,maximum:300),spacing:26)],spacing:30) {
                        ForEach(Array(filtered.enumerated()),id:\.element.id) { i,song in
                            Button { selection = song.id } label: { SongCard(song:song,number:i+1,missing:library.missing(song)) }
                                .buttonStyle(.plain)
                                .contextMenu { Button("Open Song") {selection = song.id}; Divider(); Button("Delete Song",role:.destructive) {deleting = song} }
                        }
                    }.padding(.top,4)
                }
                HStack(spacing:8) {
                    Image(systemName:"paperclip").rotationEffect(.degrees(-30))
                    Text("Drop a link, PDF, or photo of a tab anywhere. We’ll read the small print.")
                }.font(.book(13)).italic().foregroundStyle(Color.pencil).frame(maxWidth:.infinity).padding(.top,10)
            }
            .padding(.horizontal,44).padding(.vertical,36)
            .frame(maxWidth:1200)
            .frame(maxWidth:.infinity)
        }
        .background(PaperBackground())
    }

    var header: some View {
        HStack(alignment:.center,spacing:26) {
            SongArt.image(SongArt.file(forFolder:folder)).resizable().scaledToFit()
                .frame(width:104,height:104)
                .shadow(color:Color.rust.opacity(folder == "camp" ? 0.45 : 0.15),radius:24,y:6)
                .rotationEffect(.degrees(-4))
            VStack(alignment:.leading,spacing:8) {
                Text(folder == "all" ? "THE WHOLE SONGBOOK" : "A FOLDER IN YOUR SONGBOOK").font(.caption.weight(.semibold)).tracking(2.5).foregroundStyle(Color.rust)
                Text(currentFolder?.name ?? "All songs").font(.book(46,.medium)).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.6)
                if let f = currentFolder {
                    HStack(alignment:.firstTextBaseline,spacing:8) {
                        Image(systemName:"pencil.line").foregroundStyle(Color.pencil)
                        Text(f.rule).font(.book(14)).italic().foregroundStyle(Color.pencil).lineLimit(1).truncationMode(.tail).help(f.rule)
                        Button { Task { await library.rankFolder(f) } } label: { Image(systemName:"arrow.triangle.2.circlepath") }
                            .buttonStyle(.borderless).foregroundStyle(Color.rust)
                            .help("Refile and rank with AI").disabled(library.busy)
                    }
                } else {
                    Text("Everything you’ve ever dropped in, in no particular order of virtue.").font(.book(15)).italic().foregroundStyle(Color.pencil)
                }
            }
            Spacer(minLength:0)
        }
    }

    var emptyState: some View {
        VStack(spacing:16) {
            HStack(spacing:-14) {
                ForEach(["lantern.png","guitar.png","mug.png"],id:\.self) { file in
                    SongArt.image(file).resizable().scaledToFit().frame(height:file == "guitar.png" ? 110 : 70)
                        .rotationEffect(.degrees(file == "lantern.png" ? -8 : file == "mug.png" ? 8 : 0))
                }
            }
            Text(query.isEmpty ? "Room for a song" : "Nothing by that name").font(.book(24,.medium)).foregroundStyle(Color.ink)
            Text(query.isEmpty ? "Drop a tab, photo, or link here. This folder will decide if it belongs." : "Try a chord, like “Em”, or part of a title.").font(.book(14)).italic().foregroundStyle(Color.pencil)
            if query.isEmpty { Button("Add a Song…") { addSong = true }.buttonStyle(.borderedProminent).tint(.rust) }
        }.frame(maxWidth:.infinity).padding(.vertical,40)
    }
}

struct PracticeChoice: Identifiable { let id = UUID(); let song:Song; let memory:Bool }

struct Sidebar: View {
    @EnvironmentObject var library: Library
    @Binding var folder: String
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:12) {
                SongArt.image("campfire.png").resizable().scaledToFit().frame(width:38,height:40)
                VStack(alignment:.leading,spacing:1) {
                    Text("Fireside").font(.book(20,.semibold))
                    Text("A few chords. Good company.").font(.book(11)).italic().foregroundStyle(.secondary)
                }
            }.padding(.horizontal,20).padding(.top,14).padding(.bottom,10)
            List(selection:$folder) {
                row("All songs",file:"guitar.png",count:library.songs.count).tag("all")
                Section("Folders") {
                    ForEach(library.folders) { f in
                        row(f.name,file:SongArt.file(forFolder:f.id),count:library.songs.filter{$0.folders.contains(f.id)}.count).tag(f.id)
                    }
                }
            }.listStyle(.sidebar)
            TwentyCard(earned:library.memorized).padding(14)
        }
    }
    func row(_ name:String,file:String,count:Int) -> some View {
        Label {
            HStack { Text(name).lineLimit(1); Spacer(); Text("\(count)").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
        } icon: {
            SongArt.image(file).resizable().scaledToFit().frame(width:18,height:18)
        }
    }
}

struct TwentyCard: View {
    let earned: Int
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.firstTextBaseline) {
                Text("THE TWENTY").font(.caption2.weight(.bold)).tracking(2.5).foregroundStyle(Color.rust)
                Spacer()
                Text(earned >= 20 ? "Done. Light the fire." : "\(20-earned) to go").font(.book(11)).italic().foregroundStyle(Color.pencil)
            }
            HStack(alignment:.firstTextBaseline,spacing:4) {
                Text("\(earned)").font(.book(40,.medium)).contentTransition(.numericText()).foregroundStyle(Color.ink)
                Text("of 20 by heart").font(.book(13)).foregroundStyle(Color.pencil)
            }
            PickTally(earned:earned)
            Text("Earned from memory. No honor system required.").font(.system(size:10.5)).foregroundStyle(Color.pencil)
        }
        .padding(14)
        .background(Color.paperCard,in:RoundedRectangle(cornerRadius:8))
        .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Color.ink.opacity(0.08)))
        .overlay(alignment:.top) { TapeStrip(angle:2).offset(y:-9) }
        .rotationEffect(.degrees(-1))
        .shadow(color:.black.opacity(0.08),radius:4,y:2)
    }
}

/// A ticket stub: songs you can play tonight.
struct PlayableTicket: View {
    let count: Int, total: Int, byHeart: Int
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:6) {
                Text("PLAYABLE TONIGHT").font(.caption2.weight(.bold)).tracking(2.5).foregroundStyle(Color.sage)
                HStack(alignment:.firstTextBaseline,spacing:6) {
                    Text("\(count)").font(.system(size:64,weight:.bold,design:.serif)).foregroundStyle(Color.ink).contentTransition(.numericText())
                    Text(count == 1 ? "song" : "songs").font(.book(18)).italic().foregroundStyle(Color.pencil)
                }
                Text(count == total && total > 0 ? "Every song in the book. Show-off." : "with the chords already in your hands").font(.book(13)).foregroundStyle(Color.pencil)
            }.padding(22)
            Spacer(minLength:0)
            Perforation()
            VStack(spacing:4) {
                Text("\(byHeart)").font(.book(26,.semibold)).foregroundStyle(Color.rust)
                Text("BY\nHEART").font(.system(size:9,weight:.bold)).tracking(1.5).multilineTextAlignment(.center).foregroundStyle(Color.pencil)
            }.frame(width:82)
        }
        .ticket()
        .accessibilityElement(children:.combine)
    }
}

/// A ticket stub: the one chord that would open up the most songs.
struct UnlockTicket: View {
    let chord: String, count: Int
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:6) {
                Text("LEARN NEXT").font(.caption2.weight(.bold)).tracking(2.5).foregroundStyle(Color.rust)
                Text(count > 0 ? chord : "—").font(.system(size:64,weight:.bold,design:.serif)).foregroundStyle(Color.ink)
                Text(count > 0 ? "opens up \(count) more \(count == 1 ? "song" : "songs")" : "No single chord stands between you and anything.").font(.book(13)).foregroundStyle(Color.pencil)
            }.padding(22)
            Spacer(minLength:0)
            if count > 0 {
                Perforation()
                ChordDiagram(chord:chord,width:58,highlight:.rust,showName:false).frame(width:100)
            }
        }
        .ticket()
        .accessibilityElement(children:.combine)
    }
}

struct Perforation: View {
    var body: some View {
        Line().stroke(Color.pencil.opacity(0.4),style:StrokeStyle(lineWidth:1.2,dash:[4,4])).frame(width:1).padding(.vertical,12)
    }
    struct Line: Shape { func path(in r: CGRect) -> Path { var p = Path(); p.move(to:CGPoint(x:r.midX,y:r.minY)); p.addLine(to:CGPoint(x:r.midX,y:r.maxY)); return p } }
}

extension View {
    func ticket() -> some View {
        self.frame(maxWidth:.infinity,minHeight:150)
            .background(Color.paperCard,in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Color.ink.opacity(0.09)))
            .shadow(color:Color(red:0.3,green:0.18,blue:0.06).opacity(0.1),radius:6,y:3)
    }
}

/// An index card taped into the songbook.
struct SongCard: View {
    let song: Song
    let number: Int
    let missing: [String]
    var tilt: Double { Double(stableHash(song.id) % 5) * 0.6 - 1.2 }
    var tint: Color { [Color.rust, .mustard, .sage, .pencil][stableHash(song.title) % 4] }
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            ZStack(alignment:.topLeading) {
                RadialGradient(colors:[tint.opacity(0.22),tint.opacity(0.06)],center:.center,startRadius:10,endRadius:150)
                SongArt.image(SongArt.file(for:song)).resizable().scaledToFit()
                    .padding(18).frame(maxWidth:.infinity).frame(height:150)
                    .shadow(color:.black.opacity(0.12),radius:6,y:4)
                Text(String(format:"No. %02d",number)).font(.system(size:11,weight:.semibold,design:.serif)).italic().foregroundStyle(Color.pencil).padding(10)
            }
            .frame(height:150).clipShape(RoundedRectangle(cornerRadius:5)).padding(8)
            VStack(alignment:.leading,spacing:8) {
                HStack(alignment:.top) {
                    Text(song.title).font(.book(18,.semibold)).foregroundStyle(Color.ink).lineLimit(3).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:6)
                    StateMark(state:song.state).padding(.top,3)
                }
                Text(song.artist).font(.book(12)).italic().foregroundStyle(Color.pencil).lineLimit(1)
                Spacer(minLength:2)
                HStack(spacing:5) {
                    ForEach(song.chords.prefix(6),id:\.self) { chord in
                        let isNew = missing.contains(chord)
                        Text(chord).font(.system(size:12,weight:.semibold,design:.serif))
                            .padding(.horizontal,7).padding(.vertical,3)
                            .foregroundStyle(isNew ? Color.rust : Color.ink)
                            .background(isNew ? Color.rust.opacity(0.1) : Color.paperShade.opacity(0.6),in:Capsule())
                            .overlay(Capsule().strokeBorder(isNew ? Color.rust.opacity(0.6) : .clear,style:StrokeStyle(lineWidth:1,dash:[3,2])))
                    }
                    if song.chords.count > 6 { Text("+\(song.chords.count-6)").font(.caption).foregroundStyle(Color.pencil) }
                }
                Text(missing.isEmpty ? "You know every chord." : "New for you: \(missing.joined(separator:", "))")
                    .font(.system(size:11)).foregroundStyle(missing.isEmpty ? Color.sage : Color.rust)
            }
            .padding(.horizontal,16).padding(.bottom,16).padding(.top,4)
        }
        .frame(maxWidth:.infinity,minHeight:318,alignment:.top)
        .background(Color.paperCard,in:RoundedRectangle(cornerRadius:6))
        .overlay(RoundedRectangle(cornerRadius:6).strokeBorder(Color.ink.opacity(0.08)))
        .overlay(alignment:.top) { TapeStrip(angle:tilt * -2.5).offset(y:-10) }
        .contentShape(Rectangle())
        .modifier(LiftOnHover(tilt:tilt))
        .accessibilityElement(children:.combine)
    }
}
