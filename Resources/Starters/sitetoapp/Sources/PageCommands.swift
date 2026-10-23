import SwiftUI

/// The site window's menu commands, for whichever site window is in front.
struct PageCommands: Commands {
    @FocusedObject var web: WebModel?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Link…") { web?.promptForLink() }
                .keyboardShortcut("l")
                .disabled(web == nil)
            Button("Copy Link") { web?.copyLink() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(web == nil)
            Button("Open in Browser") { web?.openInBrowser() }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(web == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("Reload Page") { web?.reload() }
                .keyboardShortcut("r")
                .disabled(web == nil)
            Button("Back") { web?.goBack() }
                .keyboardShortcut("[")
                .disabled(web?.canGoBack != true)
            Button("Forward") { web?.goForward() }
                .keyboardShortcut("]")
                .disabled(web?.canGoForward != true)
            Button("Home") { web?.goHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(web == nil)
            Divider()
            Button("Zoom In") { web?.zoom(1) }
                .keyboardShortcut("+")
                .disabled(web == nil)
            Button("Zoom Out") { web?.zoom(-1) }
                .keyboardShortcut("-")
                .disabled(web == nil)
            Button("Actual Size") { web?.zoom(0) }
                .keyboardShortcut("0")
                .disabled(web == nil)
            Divider()
        }
    }
}
