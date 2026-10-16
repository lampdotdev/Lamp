import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CountdownStore

    var body: some View {
        Form {
            Toggle("Show days to the next countdown in the menu bar", isOn: $store.prefs.showsDaysInMenuBar)
            if store.hasExamples {
                LabeledContent("Sample countdowns") {
                    Button("Clear Examples") { store.clearExamples() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
