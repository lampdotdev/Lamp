import SwiftUI

struct Song: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title: String
    var artist: String
    var chords: [String]
    var sequence: [String]
    var tuning: String
    var pattern: String
    var notes: String
    var difficulty: String
    var folders: [String]
    var ranks: [String: Double]
    var state = "reading it"
    var source: String?
    var learned: Date?
    var art: String?
}
struct SongFolder: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var rule: String
}
struct PracticeRecord: Codable, Identifiable {
    var id = UUID().uuidString
    var song: String
    var date = Date()
    var completed: Bool
}

@MainActor final class Library: ObservableObject {
    static let shared = Library()
    @Published var songs: [Song] = []
    @Published var folders: [SongFolder] = []
    @Published var busy = false
    @Published var message: String?
    @Published var known = LampStore.load([String].self, from: "known") ?? ["G","C","D","Em","Am","E","A","Dm"]
    @Published var nudges = LampStore.load(Bool.self, from: "nudges") ?? false
    let songStore = LampStore.collection("songs", of: Song.self)
    let folderStore = LampStore.collection("folders", of: SongFolder.self)
    let records = LampStore.collection("practice", of: PracticeRecord.self)
    private var serviceStarted = false
    private var schedule: LampSchedule?
    private var captureKey: LampHotKey?
    func startServices() {
        guard !serviceStarted else { return }; serviceStarted = true
        captureKey = LampHotKey("control+option+cmd+g") { [weak self] in
            guard let self, !self.busy else { return }
            do {
                let url = try SongCapture.browserURL()
                Task {
                    await self.receive([url])
                    LampNotifications.send("Fireside",body:self.message ?? "The page has been read.")
                    self.message = nil
                }
            } catch { LampNotifications.send("Couldn’t save this page",body:error.localizedDescription) }
        }
        LampShare.onReceive { items in
            var urls: [URL] = []
            var texts: [String] = []
            for item in items {
                if let data = item.data {
                    let name = UUID().uuidString + "." + (item.fileURL?.pathExtension ?? "txt")
                    let url = LampStore.folder.appendingPathComponent(name)
                    do { try data.write(to:url); urls.append(url) } catch { self.message = error.localizedDescription }
                } else if let url = item.url { urls.append(url) }
                else if let text = item.text { texts.append(text) }
            }
            Task {
                await self.receive(urls)
                for text in texts { await self.importSong(text) }
            }
        }
        schedule = LampSchedule.every("monthly-check",minutes:60) { [weak self] in self?.monthlyNote() }
        Task { await pickArt() }
    }
    /// Gives each song a painting that suits it, judged once.
    func pickArt() async {
        let bare = songs.filter { $0.art == nil }
        guard !bare.isEmpty, await LampAI.isAvailable(.decisions) else { return }
        let options = SongArt.all.map(\.meaning)
        guard let verdicts = try? await LampAI.choose("Which picture best suits this song's mood and subject?",from:options,each:bare,remember:2_592_000,about:{ ["title":$0.title,"artist":$0.artist,"notes":$0.notes] }) else { return }
        for v in verdicts {
            guard let choice = v.choice, let file = SongArt.all.first(where:{$0.meaning == choice})?.file,
                  var song = songs.first(where:{$0.id == v.item.id}), song.art == nil else { continue }
            song.art = file; save(song)
        }
    }
    func monthlyNote() {
        guard nudges else { return }
        let now = Date()
        let previous = LampStore.load(Date.self,from:"monthly-date") ?? now
        if LampStore.load(Date.self,from:"monthly-date") == nil { LampStore.save(now,to:"monthly-date"); return }
        guard now >= Calendar.current.date(byAdding:.month,value:1,to:previous)! else { return }
        let newlyEarned = songs.filter { ($0.learned ?? .distantPast) > previous }
        let names = newlyEarned.prefix(3).map(\.title).joined(separator:", ")
        LampNotifications.send("A month of music",body:newlyEarned.isEmpty ? "Your songbook is here whenever you fancy a strum." : "\(newlyEarned.count) more songs from memory: \(names).",id:"monthly")
        LampStore.save(now,to:"monthly-date")
    }
    init() {
        folders = folderStore.all()
        songs = songStore.all()
        if folders.isEmpty {
            folders = [SongFolder(id:"camp", name:"Campfire", rule:"Singable, familiar songs for friends around a campfire. Open chords, no barre chords, no lead guitarist. Rank the most singable first."), SongFolder(id:"sad",name:"Fingerpicked and sad",rule:"Melancholy songs that suit gentle fingerpicking."), SongFolder(id:"bed",name:"Bedtime songs for Mila",rule:"Gentle, reassuring songs to sing a child to sleep.")]
            folders.forEach { folderStore.put($0) }
        }
        if !((LampStore.load(Bool.self, from:"seeded")) ?? false) {
            seed(); LampStore.save(true,to:"seeded")
        }
    }
    var playable: Int { songs.filter { missing($0).isEmpty }.count }
    var memorized: Int { songs.filter { $0.state == "know it by heart" }.count }
    func missing(_ song: Song) -> [String] { Set(song.chords).subtracting(known).sorted() }
    var unlock: (String,Int) {
        let candidates = Set(songs.flatMap { missing($0) })
        var result: [(String,Int)] = []
        for chord in candidates {
            let count = songs.filter { missing($0) == [chord] }.count
            result.append((chord,count))
        }
        result.sort { left,right in
            if left.1 == right.1 { return left.0 < right.0 }
            return left.1 > right.1
        }
        return result.first ?? ("—",0)
    }
    func save(_ song: Song) {
        songStore.put(song)
        if let i = songs.firstIndex(where: {$0.id == song.id}) { songs[i] = song } else { songs.append(song) }
        LampSpotlight.index(id:song.id,title:song.title,details:song.artist,keywords:song.chords)
    }
    func seed() {
        let titles = ["This Land Is Your Land (traditional-style study)","Amazing Grace","You Are My Sunshine (chord study)","Down in the Valley","Oh! Susanna","She’ll Be Coming ’Round the Mountain","Red River Valley","Home on the Range","Swing Low, Sweet Chariot","The Water Is Wide","Shenandoah","Goodnight, Ladies"]
        let progressions = [["G","C","G","D","G"],["G","G","C","G","Em","D","G"],["G","G","C","G","C","G","D","G"],["G","D","D","G"],["G","C","G","D","G"],["G","G","D","G","C","G","D","G"],["G","G","D","G","C","G","D","G"],["G","C","G","D","G"],["G","C","G","Em","D","G"],["D","G","D","A","D"],["C","F","C","Am","G","C"],["G","D","G","C","G","D","G"]]
        for i in titles.indices {
            let p = progressions[i]
            save(Song(title:titles[i],artist:"Songbook arrangement",chords:Array(Set(p)).sorted(),sequence:Array(repeating:p,count:3).flatMap{$0},tuning:"Standard · E A D G B E",pattern:i > 8 ? "Gentle thumb–index–middle–ring, one cycle per chord." : "Down, down-up, up-down-up; one bar per chord.",notes:"A simple three-verse practice arrangement. Each chord tile is one bar. No lyrics or lead part; sing the melody you know. Adjust the arrangement after importing your preferred version.",difficulty:i == 10 ? "One new chord: F" : "Easy · open chords",folders:i > 8 ? ["camp","sad","bed"] : ["camp"],ranks:["camp":Double(12-i),"sad":Double(i),"bed":Double(i)]))
        }
    }
    func record(_ song: Song, completed: Bool) {
        records.put(PracticeRecord(song:song.id,completed:completed))
        guard nudges else { return }
        let all = records.all()
        if all.count >= 3 {
            let hours = Dictionary(grouping:all,by:{Calendar.current.component(.hour,from:$0.date)})
            if let hour = hours.max(by:{$0.value.count < $1.value.count})?.key,
               let next = Calendar.current.nextDate(after:Date(), matching:DateComponents(hour:hour,minute:0),matchingPolicy:.nextTime) {
                LampNotifications.send("Your guitar is still there",body:"A song or two? No stadium required.",at:next,id:"habit")
            }
        }
        monthlyNote()
    }
}
