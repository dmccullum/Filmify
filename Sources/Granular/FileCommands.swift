import AppKit
import SwiftUI

/// File menu: opening, moving between, exporting, sharing and revealing images.
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
                if model.openImageURLs.count > 1 {
                    Button("Close All Images") {
                        model.closeAllImages()
                    }
                }
            }

            if model.operationMode == .edit {
                Divider()

                Button("Next Image") {
                    moveInTextOrShow(#selector(NSResponder.moveToRightEndOfLine(_:)), model.showNextImage)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(!model.canShowNextImage)

                Button("Previous Image") {
                    moveInTextOrShow(#selector(NSResponder.moveToLeftEndOfLine(_:)), model.showPreviousImage)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(!model.canShowPreviousImage)
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

                Button("Export All…") {
                    model.exportAllImages()
                }
                .disabled(model.openImageURLs.isEmpty || model.batchExport != nil)

                if let source = model.selectedSourceURL {
                    ShareLink(
                        item: model.processedImageItem(for: source),
                        preview: SharePreview(model.exportFileName(for: source))
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

    /// ⌘← and ⌘→ still move to the ends of the line while typing; otherwise
    /// they move along the open images.
    private func moveInTextOrShow(_ textCommand: Selector, _ showImage: () -> Void) {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.isEditable {
            textView.doCommand(by: textCommand)
        } else {
            showImage()
        }
    }
}
