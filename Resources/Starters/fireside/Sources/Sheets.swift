import SwiftUI
import UniformTypeIdentifiers

struct FolderSheet: View {
    @EnvironmentObject var library:Library
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var rule = ""
    var body: some View {
        Form { Text("A folder with a point of view").font(.system(.title2,design:.serif)); TextField("Folder name",text:$name); TextField("What belongs here?",text:$rule,axis:.vertical).lineLimit(3...6); Text("Try “Only songs in drop D” or “Stuff my dad would sing along to.”").font(.caption).foregroundStyle(.secondary); HStack {Button("Cancel") {dismiss()}; Spacer(); Button("Create Folder") {Task {await library.addFolder(name:name,rule:rule)}; dismiss()}.disabled(name.isEmpty || rule.isEmpty) } }.padding(24).frame(width:480)
    }
}
struct ImportSheet: View {
    @EnvironmentObject var library:Library
    @Environment(\.dismiss) var dismiss
    @State private var input = ""
    @State private var files = false
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Another one for the songbook").font(.system(.title2,design:.serif))
            Text("Paste a link or tab. AI reads the arrangement and finds its folders.").foregroundStyle(.secondary)
            TextEditor(text:$input).font(.body.monospaced()).frame(height:180).border(.quaternary)
            HStack {Button("Choose PDF or photo…") {files = true}; Spacer(); Button("Cancel") {dismiss()}; Button("Read and File") {let value = input; dismiss(); Task {if let url = URL(string:value.trimmingCharacters(in:.whitespacesAndNewlines)),["http","https"].contains(url.scheme ?? "") {await library.receive([url])} else {await library.importSong(value)}}}.disabled(input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || library.busy) }
        }.padding(26).frame(width:580)
            .fileImporter(isPresented:$files,allowedContentTypes:[.pdf,.image,.plainText],allowsMultipleSelection:true) { result in if case .success(let urls) = result {dismiss(); Task {await library.receive(urls)}} }
    }
}
struct ArrangementSheet: View {
    @EnvironmentObject var library:Library
    @Environment(\.dismiss) var dismiss
    let song:Song
    @State private var sequence = ""
    @State private var tuning = ""
    @State private var pattern = ""
    var body: some View {
        Form {
            Text("Your arrangement").font(.title2)
            TextField("Tuning",text:$tuning)
            TextField("Strumming or picking",text:$pattern,axis:.vertical)
            Text("Full song, one chord per bar. Repeat every verse and chorus explicitly.").font(.caption)
            TextEditor(text:$sequence).font(.body.monospaced()).frame(height:180)
            HStack {Button("Cancel") {dismiss()}; Spacer(); Button("Save") { var s = song; s.sequence = sequence.split(whereSeparator:{$0.isWhitespace || $0 == "," || $0 == "|"}).map(String.init); s.chords = Array(Set(s.sequence)).sorted(); s.tuning = tuning; s.pattern = pattern; s.state = "reading it"; s.learned = nil; library.save(s); dismiss() } }
        }.padding(24).frame(width:550).onAppear {sequence = song.sequence.joined(separator:" "); tuning = song.tuning; pattern = song.pattern}
    }
}
