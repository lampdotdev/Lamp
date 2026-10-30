import SwiftUI
import AppKit

/// Lamp's own About window. The standard panel has no room for a line under the app's name, so this one
/// lays out the same things (icon, name, version) with the tagline between them.
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Lamp") { openWindow(id: "about") }
        }
    }
}

struct AboutScene: Scene {
    var body: some Scene {
        Window("About Lamp", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()   // no "About Lamp" entry in the Window menu
    }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String
        return build.map { $0 == short ? "Version \(short)" : "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .padding(.bottom, 12)
            Text("Lamp").font(.title2.bold())
            Text("Remixable software for the things you already own.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Text(version)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 14)
            Text("© Roo Code, Inc")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 20)
        }
        .padding(.horizontal, 48)
        .padding(.top, 28)
        .padding(.bottom, 32)
        .fixedSize()
    }
}
