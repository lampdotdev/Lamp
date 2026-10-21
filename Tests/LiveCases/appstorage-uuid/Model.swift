import SwiftUI
struct Settings: View { @State private var on = false; var body: some View { Toggle("on", isOn: $on) } }
struct Item: Codable { var name: String }
