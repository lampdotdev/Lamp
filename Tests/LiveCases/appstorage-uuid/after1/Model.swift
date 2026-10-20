import SwiftUI
struct Settings: View { @State private var on = false; @AppStorage("size") private var size = 12; var body: some View { Toggle("on \(size)", isOn: $on) } }
struct Item: Codable { var name: String }
