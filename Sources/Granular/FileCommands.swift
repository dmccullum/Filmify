import SwiftUI

/// File menu: opening, exporting and revealing images.
struct FileCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(model.operationMode == .drop ? "Process Images…" : "Open Image…") {
                model.chooseImages()
            }
            .keyboardShortcut("o")

            if model.operationMode == .edit, model.selectedSourceURL != nil {
                Button("Close Image") {
                    model.closeEditorImage()
                }
            }

            Divider()

            Button("Choose Instant Output Folder…") {
                model.chooseDropOutputFolder()
            }
            if model.operationMode == .edit {
                Button("Export…") {
                    model.exportEditedImage()
                }
                .keyboardShortcut("s")
                .disabled(model.selectedSourceURL == nil || model.isExporting)
            }

            Button("Reveal Last Output") {
                model.revealLastOutput()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.completedJobCount == 0)
        }
    }
}
