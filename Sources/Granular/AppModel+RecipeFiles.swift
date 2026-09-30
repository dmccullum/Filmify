import AppKit
import GranularCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A recipe saved as a file, declared in Info.plist.
    static let granularRecipe = UTType(exportedAs: RecipeFile.typeIdentifier, conformingTo: .json)
}

extension Notification.Name {
    /// Recipe files have arrived from the Finder and are waiting in the inbox.
    static let granularOpenRecipeFiles = Notification.Name("GranularOpenRecipeFiles")
}

/// Recipe files opened from the Finder or dropped on the Dock icon. They wait
/// here until a window can import them, since at launch they can arrive
/// before any window is listening.
@MainActor
enum RecipeFileInbox {
    private static var pending: [URL] = []

    static func receive(_ urls: [URL]) {
        pending.append(contentsOf: urls)
        NotificationCenter.default.post(name: .granularOpenRecipeFiles, object: nil)
    }

    static func take() -> [URL] {
        defer { pending = [] }
        return pending
    }
}

// Recipes as files: importing, exporting and dragging them out.
extension AppModel {
    /// Adds the recipes in these files to the library, each under a name of
    /// its own and in its own canister, and shows the last one there.
    @discardableResult
    func importRecipes(from urls: [URL], in window: RecipeWindow? = nil) -> [FilmRecipe] {
        var imported: [FilmRecipe] = []
        var failures: [(name: String, error: Error)] = []
        var names = availableRecipes.map(\.name)

        for url in urls where !Self.isRecipeDraggedFromLibrary(url) {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let file = try RecipeFile.decode(
                    Data(contentsOf: url),
                    fallbackName: url.deletingPathExtension().lastPathComponent
                )
                var recipe = file.recipe
                recipe.id = "custom-\(UUID().uuidString)"
                recipe.name = FilmRecipe.uniqueName(recipe.name, among: names)
                names.append(recipe.name)
                imported.append(recipe)
            } catch {
                failures.append((url.lastPathComponent, error))
            }
        }

        if !imported.isEmpty {
            changeRecipes(imported.count == 1 ? "Import Recipe" : "Import Recipes", in: window) {
                savedRecipes.append(contentsOf: imported)
                persistRecipes()
            }
            recipeLibrarySelection = imported.last?.id
            statusMessage = imported.count == 1
                ? "Imported recipe “\(imported[0].name)”"
                : "Imported \(imported.count) recipes"
        }
        if let failure = failures.first {
            recipeLibraryAlert = RecipeLibraryAlert(
                title: failures.count == 1
                    ? "“\(failure.name)” couldn’t be imported."
                    : "\(failures.count) files couldn’t be imported.",
                message: failure.error.localizedDescription
            )
        }
        return imported
    }

    /// Asks for recipe files to import, then shows the library.
    func chooseRecipesToImport(then showLibrary: @escaping () -> Void = {}) {
        let panel = NSOpenPanel()
        panel.title = "Import Recipes"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.granularRecipe]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let window = activeRecipeWindow
        present(panel, in: window) { [weak self] response in
            guard response == .OK, let self else { return }
            self.importRecipes(from: panel.urls, in: window)
            showLibrary()
        }
    }

    /// Saves a recipe to a file wherever the user likes.
    func exportRecipe(_ recipe: FilmRecipe) {
        let panel = NSSavePanel()
        panel.title = "Export Recipe"
        panel.prompt = "Export"
        panel.nameFieldStringValue = RecipeFile.fileName(for: recipe)
        panel.allowedContentTypes = [.granularRecipe]
        panel.canCreateDirectories = true
        present(panel, in: activeRecipeWindow) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try RecipeFile(recipe: recipe).encoded().write(to: url, options: .atomic)
                self?.statusMessage = "Exported recipe “\(recipe.name)”"
            } catch {
                self?.recipeLibraryAlert = RecipeLibraryAlert(
                    title: "“\(recipe.name)” couldn’t be exported.",
                    message: error.localizedDescription
                )
            }
        }
    }

    /// A recipe as a file, for dragging out of the library into the Finder
    /// or anywhere else that takes files.
    func recipeItemProvider(for recipe: FilmRecipe) -> NSItemProvider {
        guard let url = try? Self.writeRecipeForTransfer(recipe),
              let provider = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
        provider.suggestedName = recipe.name
        return provider
    }

    private static func writeRecipeForTransfer(_ recipe: FilmRecipe) throws -> URL {
        let url = try TransferFiles.makeDestination(named: RecipeFile.fileName(for: recipe))
        try RecipeFile(recipe: recipe).encoded().write(to: url, options: .atomic)
        return url
    }

    /// A recipe dragged out of the library and let go over it again stays put
    /// rather than coming back in as a copy.
    private static func isRecipeDraggedFromLibrary(_ url: URL) -> Bool {
        let transfers = FileManager.default.temporaryDirectory
            .appending(path: "Granular Transfers", directoryHint: .isDirectory)
            .resolvingSymlinksInPath().path
        return url.resolvingSymlinksInPath().path.hasPrefix(transfers)
    }

    /// Shows a file panel as a sheet on the window the request came from.
    private func present(
        _ panel: NSSavePanel,
        in window: RecipeWindow,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        let host = window == .library ? recipeLibraryWindow : mainWindow
        if let host, host.isVisible, host.attachedSheet == nil {
            panel.beginSheetModal(for: host, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}
