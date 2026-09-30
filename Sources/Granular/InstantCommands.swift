import SwiftUI

/// File menu: Quick Look for the marked frame, stopping a batch, and saving
/// frames that are waiting on Ask Each Time.
struct InstantCommands: Commands {
    let model: AppModel
    private var roll: FilmRoll { .shared }

    var body: some Commands {
        CommandGroup(after: .importExport) {
            // Both act on the film strip, so Edit mode's File menu leaves them out.
            if model.operationMode == .drop {
                Divider()

                Button(quickLookTitle) {
                    FramePreviewController.shared.togglePanel()
                }
                .keyboardShortcut("y")
                .disabled(roll.selectedFrameID == nil)

                Button("Cancel Processing") {
                    model.cancelInstantProcessing()
                }
                .keyboardShortcut(".")
                .disabled(!model.canCancelProcessing)

                // Frames developed under Ask Each Time that haven’t been saved yet.
                Button("Save Unsaved Images…") {
                    model.saveAllUnsaved()
                }
                .disabled(model.unsavedJobIDs.isEmpty)
            }
        }
    }

    private var quickLookTitle: String {
        guard model.operationMode == .drop,
              let id = roll.selectedFrameID,
              let job = model.job(id) else { return "Quick Look" }
        let name = switch job.state {
        case .finished(let output): output.lastPathComponent
        default: job.sourceURL.lastPathComponent
        }
        return "Quick Look “\(name)”"
    }
}
