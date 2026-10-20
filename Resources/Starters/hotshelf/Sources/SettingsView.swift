import SwiftUI

struct SettingsView: View {
    @AppStorage("tasteProfile") private var profile = defaultTasteProfile
    @AppStorage("nudge.friday") private var friday = true
    @AppStorage("nudge.quarterly") private var quarterly = true

    var body: some View {
        Form {
            Section {
                TextEditor(text: $profile)
                    .font(.body)
                    .frame(height: 90)
            } header: {
                Text("Your taste")
            } footer: {
                Text("Used to read bottles, pick tonight's sauce and spot gaps on your shelf.")
            }
            Section("Nudges") {
                Toggle("Friday evening: open something forgotten", isOn: $friday)
                Toggle("Every quarter: finished vs. bought", isOn: $quarterly)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onChange(of: friday) { Nudges.reschedule(Shelf.shared.bottles) }
        .onChange(of: quarterly) { Nudges.reschedule(Shelf.shared.bottles) }
    }
}
