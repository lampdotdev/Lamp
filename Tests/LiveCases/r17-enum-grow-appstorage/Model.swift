import SwiftUI
enum Theme: String, CaseIterable { case light, dark }
struct SettingsPane: View {
    @AppStorage("r17-theme") private var theme: Theme = .light
    var body: some View { Picker("Theme", selection: $theme) { ForEach(Theme.allCases, id: \.self) { Text($0.rawValue) } } }
}
@MainActor func probe() -> String { Theme.allCases.map(\.rawValue).joined(separator: " ") }
