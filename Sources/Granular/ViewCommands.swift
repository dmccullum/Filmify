import SwiftUI

struct MainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .windowList) {
            // No shortcut: ⌘0 belongs to View ▸ Actual Size.
            Button("Granular") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
        }
    }
}

struct ViewerCommands: Commands {
    @FocusedValue(\.granularViewerZoomController) private var zoomController
    let model: AppModel

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(OperationMode.allCases) { mode in
                Toggle(mode.rawValue, isOn: Binding(
                    get: { model.operationMode == mode },
                    set: { isOn in
                        if isOn { model.operationMode = mode }
                    }
                ))
                .keyboardShortcut(mode == .drop ? "1" : "2", modifiers: [.command])
            }

            Divider()
        }

        CommandGroup(after: .toolbar) {
            Button(model.showOriginal ? "Show Processed" : "Show Original") {
                model.showOriginal.toggle()
            }
            .keyboardShortcut("\\", modifiers: [])
            .disabled(model.operationMode != .edit || model.sourcePreview == nil)

            Divider()

            Button("Actual Size") {
                zoomController?.actualSize()
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(!canZoom)

            Button("Zoom to Fit") {
                zoomController?.fit()
            }
            .keyboardShortcut("9", modifiers: [.command])
            .disabled(!canZoom)

            Button("Zoom In") {
                zoomController?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(!canZoom)

            Button("Zoom Out") {
                zoomController?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(!canZoom)
        }
    }

    private var canZoom: Bool {
        model.operationMode == .edit && model.sourcePreview != nil && zoomController != nil
    }
}
