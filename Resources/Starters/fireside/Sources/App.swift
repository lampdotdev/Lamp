import SwiftUI

@main
struct MainApp: SwiftUI.App {
    @StateObject private var library = Library.shared
    var body: some SwiftUI.Scene {
        WindowGroup("Fireside") {
            ContentView().environmentObject(library)
                .task { library.startServices() }
        }
        .commands { LampCommands() }
        Settings { SongbookSettings().environmentObject(library) }
    }
}

struct SongbookSettings: View {
    @EnvironmentObject var library:Library
    var body: some View {
        Form {
            Section("Chords in your hands") {
                ForEach(["G","C","D","Em","Am","E","A","Dm","F","B7","D7","G7","Cadd9"],id:\.self) { chord in
                    Toggle(chord,isOn:Binding(get:{library.known.contains(chord)},set:{ on in
                        if on { library.known.append(chord) } else { library.known.removeAll {$0 == chord} }
                        LampStore.save(library.known,to:"known")
                    }))
                }
            }
            Section("A gentle nudge") {
                Toggle("Practice reminders and monthly notes",isOn:$library.nudges).onChange(of:library.nudges) { _,value in
                    LampStore.save(value,to:"nudges")
                    if value { LampNotifications.send("No daily guilt trip",body:"After a few sessions, we’ll learn your usual guitar hour.") }
                    else { LampNotifications.cancel("habit"); LampNotifications.cancel("monthly") }
                }
                Text("Reminders learn from practice sessions. Monthly notes compare your earned songs. Nothing is recorded or uploaded.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Listening recognizes common open chords, F, B7, D7, G7, and Cadd9. Use your Mac’s preferred audio input; interfaces use the channel with the strongest signal.").font(.caption).foregroundStyle(.secondary)
            Text("Press ⌃⌥⌘G in Safari, Chrome, or Arc to save the current tab without leaving it.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).frame(width:460,height:650)
    }
}
