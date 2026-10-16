import SwiftUI

/// The folder shown in the focused window, so the Tidy menu acts on what the person is looking at.
struct SelectedFolderKey: FocusedValueKey {
    typealias Value = UUID
}

extension FocusedValues {
    var selectedFolder: UUID? {
        get { self[SelectedFolderKey.self] }
        set { self[SelectedFolderKey.self] = newValue }
    }
}

/// The Tidy menu: the toolbar's actions with their shortcuts, and Clear Examples.
struct TidyCommands: Commands {
    @ObservedObject var model: TidyModel
    @FocusedValue(\.selectedFolder) private var folderID

    var body: some Commands {
        CommandMenu("Tidy") {
            Button("Tidy Now") {
                if let folderID { model.tidyNow(folderID) }
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(!model.canTidy(folderID))

            Button("Undo Last Tidy") {
                if let folderID { model.undoLastTidy(in: folderID) }
            }
            .keyboardShortcut("z", modifiers: [.command, .option])
            .disabled(model.folder(folderID).flatMap(model.undoable(in:)) == nil)

            Divider()

            Button("Add Folder…") { model.addFolder() }
                .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("Clear Examples") { model.clearExamples() }
                .disabled(!model.hasExamples)
        }
    }
}
