import SwiftUI

struct MainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .windowList) {
            Button("Granular") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("0", modifiers: [.command])
        }
    }
}

struct ViewerCommands: Commands {
    @FocusedValue(\.granularViewerZoomController) private var zoomController
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(model.showOriginal ? "Show Processed" : "Show Original") {
                model.showOriginal.toggle()
            }
            .keyboardShortcut("\\", modifiers: [])
            .disabled(model.operationMode != .edit || model.sourcePreview == nil)

            Divider()

            Button("Zoom In") {
                zoomController?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(model.operationMode != .edit || model.sourcePreview == nil || zoomController == nil)

            Button("Zoom Out") {
                zoomController?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(model.operationMode != .edit || model.sourcePreview == nil || zoomController == nil)

            Button("Zoom to Fit") {
                zoomController?.fit()
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(model.operationMode != .edit || model.sourcePreview == nil || zoomController == nil)
        }
    }
}
