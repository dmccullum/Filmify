import AppKit
import GranularCore
import SwiftUI

extension Notification.Name {
    static let granularOpenURLs = Notification.Name("GranularOpenURLs")
}

final class GranularApplicationDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .granularOpenURLs, object: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct GranularDesktopApp: App {
    @NSApplicationDelegateAdaptor(GranularApplicationDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        @Bindable var model = model

        Window("Granular", id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 700, height: 400)
        .restorationBehavior(.disabled)
        .commands {
            AboutCommands()
            MainWindowCommands()
            ViewerCommands(model: model)

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

            CommandMenu("Recipe") {
                ForEach(model.availableRecipes) { recipe in
                    Button(recipe.name) {
                        model.selectRecipe(recipe)
                    }
                }

                Divider()

                Button("Save New Recipe…") {
                    model.beginSavingRecipe()
                }
                .disabled(model.operationMode != .edit)

                Button("Manage Recipes…") {
                    model.showRecipeManager = true
                }

                if model.isSelectedRecipeCustom {
                    Button("Update Current Recipe") {
                        model.updateSelectedRecipe()
                    }
                    Button("Delete Current Recipe…", role: .destructive) {
                        model.deleteSelectedRecipe()
                    }
                }

                Divider()

                Button("New Grain Pattern") {
                    model.randomizeGrain()
                }
            }

        }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra(
            "Granular",
            systemImage: model.isWatching ? "drop.fill" : "drop",
            isInserted: $model.showMenuBarExtra
        ) {
            MenuBarStatusView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MainWindowCommands: Commands {
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

private struct ViewerCommands: Commands {
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

private struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Granular") {
                NSApp.activate(ignoringOtherApps: true)
                AboutWindowController.shared.show()
            }
        }
    }
}
