import AppKit
import GranularCore
import SwiftUI

/// The menu under Granular’s menu bar item: what it’s doing, the recipe in
/// use, the latest frames, and the way back to the window.
struct MenuBarStatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        status

        Divider()

        recipeMenu

        let recents = model.recentOutputs()
        if !recents.isEmpty {
            Section("Recent") {
                ForEach(recents, id: \.self) { url in
                    Button {
                        model.reveal(url)
                    } label: {
                        Label {
                            Text(url.lastPathComponent)
                        } icon: {
                            Image(nsImage: MenuIcons.fileIcon(for: url))
                        }
                    }
                    .help("Show in Finder. Hold Option to open it instead.")
                    .modifierKeyAlternate(.option) {
                        Button("Open “\(url.lastPathComponent)”") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }

        Divider()

        Button("Open Granular") {
            NSApp.activate()
            openWindow(id: "main")
        }
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Granular") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: Status

    @ViewBuilder
    private var status: some View {
        Text(watchingTitle)
        if let error = model.watchErrorMessage {
            Text(error)
        }
        if let batch = model.displayedBatch {
            Text("Processing \(batch.progress.position) of \(batch.progress.total)…")
        }

        if hasWatchedFolders {
            Button(model.isWatching ? "Pause Watching" : "Resume Watching") {
                model.toggleWatching()
            }
        } else {
            Button("Set Up Watched Folders…") {
                NSApp.activate()
                openSettings()
            }
        }
        if model.canCancelProcessing {
            Button("Cancel Processing") {
                model.cancelInstantProcessing()
            }
        }
    }

    private var hasWatchedFolders: Bool {
        model.watchedInputFolder != nil && model.watchedOutputFolder != nil
    }

    private var watchingTitle: String {
        if model.isWatching, let incoming = model.watchedInputFolder {
            return "Watching “\(incoming.lastPathComponent)”"
        }
        return hasWatchedFolders ? "Watching Paused" : "Not Watching a Folder"
    }

    // MARK: Recipe

    private var recipeMenu: some View {
        Menu {
            if model.isRecipeModified {
                Toggle("Custom", isOn: .constant(true))
                    .disabled(true)
            }
            Section("Built-in") {
                ForEach(FilmRecipe.builtIns) { recipe in
                    recipeItem(recipe)
                }
            }
            if !model.savedRecipes.isEmpty {
                Section("My Recipes") {
                    ForEach(model.savedRecipes) { recipe in
                        recipeItem(recipe)
                    }
                }
            }
        } label: {
            Label {
                Text("Recipe: \(model.recipeDisplayName)")
            } icon: {
                Image(nsImage: MenuIcons.canister(for: model.currentRecipe))
            }
        }
    }

    private func recipeItem(_ recipe: FilmRecipe) -> some View {
        Toggle(isOn: Binding(
            get: { !model.isRecipeModified && model.selectedRecipeID == recipe.id },
            set: { _ in model.selectRecipe(recipe) }
        )) {
            Label {
                Text(recipe.name)
            } icon: {
                Image(nsImage: MenuIcons.canister(for: recipe))
            }
        }
    }
}

/// Small images for menu items, drawn once and kept.
@MainActor
private enum MenuIcons {
    private static var canisters: [String: NSImage] = [:]
    private static var files: [URL: NSImage] = [:]

    /// A recipe’s canister at menu-item size, rendered from the same view as
    /// the one on the camera back.
    static func canister(for recipe: FilmRecipe) -> NSImage {
        let key = [recipe.id, recipe.name, recipe.canister ?? ""].joined(separator: "\u{1F}")
        if let cached = canisters[key] { return cached }

        let renderer = ImageRenderer(content: MiniCanister(recipe: recipe, height: 16))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "film", accessibilityDescription: nil) ?? NSImage()
        canisters[key] = image
        return image
    }

    static func fileIcon(for url: URL) -> NSImage {
        if let cached = files[url] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        files[url] = icon
        return icon
    }
}
