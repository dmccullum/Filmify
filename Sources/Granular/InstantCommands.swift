import SwiftUI

/// File menu: Quick Look for the marked frame, and stopping a batch.
struct InstantCommands: Commands {
    let model: AppModel
    private var roll: FilmRoll { .shared }

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Divider()

            Button(quickLookTitle) {
                FramePreviewController.shared.togglePanel()
            }
            .keyboardShortcut("y")
            .disabled(model.operationMode != .drop || roll.selectedFrameID == nil)

            Button("Cancel Processing") {
                model.cancelInstantProcessing()
            }
            .keyboardShortcut(".")
            .disabled(!model.canCancelProcessing)
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
