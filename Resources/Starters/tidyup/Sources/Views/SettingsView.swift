import SwiftUI

struct SettingsView: View {
    @State private var openAtLogin = LampLoginItem.isEnabled

    var body: some View {
        Form {
            Toggle("Open at Login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, on in
                    LampLoginItem.set(on)
                    openAtLogin = LampLoginItem.isEnabled
                }
            Text("Folders set to tidy by themselves are only tidied while Tidy Up is open.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
