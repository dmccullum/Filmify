import SwiftUI

/// Edit menu: carrying a look from one photo to the next. Undo and Redo are
/// the system's own items, driven by the main window's undo manager.
struct EditCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Copy Settings") {
                model.copySettings()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Paste Settings") {
                model.pasteSettings()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(!model.canPasteSettings)
        }
    }
}
