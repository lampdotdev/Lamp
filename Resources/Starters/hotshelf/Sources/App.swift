import AppKit
import SwiftUI

@main
struct MainApp: SwiftUI.App {
    @StateObject private var shelf = Shelf.shared

    var body: some SwiftUI.Scene {
        WindowGroup("Hot Shelf") {
            ShelfView()
                .environmentObject(shelf)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            LampCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About Hot Shelf") { About.show() }
            }
            CommandGroup(after: .newItem) {
                Button("Add Bottle…") { shelf.showAdd = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// The About box, with the credit the example bottles' photos ask for.
enum About {
    static func show() {
        let credit = NSMutableAttributedString(string: "Example bottle photos from Open Food Facts contributors, CC BY-SA 3.0. ",
                                               attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        credit.append(NSAttributedString(string: "openfoodfacts.org", attributes: [.font: NSFont.systemFont(ofSize: 11),
                                                                                  .link: URL(string: "https://world.openfoodfacts.org")!]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credit.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credit.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credit])
        NSApp.activate()
    }
}
