import AppKit
import SwiftUI

/// File menu: opening, exporting, sharing and revealing images.
///
/// It reads nothing that changes while the recipe is adjusted, so a slider
/// drag doesn’t rebuild the menu bar with every step.
struct FileCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(model.operationMode == .drop ? "Process Images…" : "Open Image…") {
                model.chooseImages()
            }
            .keyboardShortcut("o")

            // Recent images always open in Edit mode, whichever mode is showing.
            Menu("Open Recent") {
                ForEach(model.recentImages) { recent in
                    Button(RecentImageStore.menuTitle(for: recent, among: model.recentImages)) {
                        model.openRecentImage(recent)
                    }
                }
                Divider()
                Button("Clear Menu") {
                    model.clearRecentImages()
                }
                .disabled(model.recentImages.isEmpty)
            }

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
                .keyboardShortcut("e")
                .disabled(model.selectedSourceURL == nil || model.isExporting)

                if let source = model.selectedSourceURL {
                    ShareLink(
                        item: model.processedImageItem(for: source),
                        preview: SharePreview(source.deletingPathExtension().lastPathComponent)
                    ) {
                        Text("Share")
                    }
                } else {
                    Menu("Share") {}
                        .disabled(true)
                }
            }

            Button("Reveal Last Output") {
                model.revealLastOutput()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.completedJobCount == 0)
        }
    }
}
