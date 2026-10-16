import SwiftUI

@main
struct MainApp: SwiftUI.App {
    @StateObject private var library = Library()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .frame(minWidth: 680, minHeight: 440)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            LampCommands()
            ShelfCommands(library: library)
        }
    }
}

/// The menu commands. Adding and naming happen in a window's sheet, so the window in front lends its actions
/// (`ShelfActions`) and a command does nothing when no window is open.
struct ShelfCommands: Commands {
    @ObservedObject var library: Library
    @FocusedValue(\.shelfActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add \(ItemKind.singular)…") { actions?.addItem() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("New Shelf…") { actions?.newShelf() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(actions == nil)
            Divider()
            Button("Clear Examples") { library.clearExamples() }
                .disabled(!library.hasExamples)
        }
    }
}

struct ShelfActions {
    var addItem: () -> Void
    var newShelf: () -> Void
}

private struct ShelfActionsKey: FocusedValueKey {
    typealias Value = ShelfActions
}

extension FocusedValues {
    var shelfActions: ShelfActions? {
        get { self[ShelfActionsKey.self] }
        set { self[ShelfActionsKey.self] = newValue }
    }
}
