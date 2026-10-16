import SwiftUI

@main
struct MainApp: SwiftUI.App {
    @StateObject private var pet = PetModel()

    var body: some Scene {
        // The pet lives in the menu bar: its face there shows its mood, and a click opens its panel.
        LampMenuBar {
            PanelView().environmentObject(pet)
        } label: {
            MenuBarFace(pet: pet)
        }
        .commands { LampCommands() }

        Settings {
            SettingsView().environmentObject(pet)
        }
    }
}

/// The menu bar icon: the pet's face for its mood, redrawn when the mood changes.
private struct MenuBarFace: View {
    @ObservedObject var pet: PetModel

    var body: some View {
        Image(nsImage: PetFaceGlyph.image(for: pet.mood))
            .accessibilityLabel("\(pet.displayName), \(pet.mood.title.lowercased())")
    }
}
