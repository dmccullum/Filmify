import AppIntents
import AppKit
import GranularCore
import UniformTypeIdentifiers

// Shortcuts actions. They run inside Granular, so they share its recipes,
// Output settings and Instant output folder with the window.

/// A recipe as Shortcuts sees it: every built-in and saved recipe, by name.
struct RecipeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Granular Recipe"
    static let defaultQuery = RecipeQuery()

    let id: String
    let name: String
    let isBuiltIn: Bool

    init(_ recipe: FilmRecipe) {
        id = recipe.id
        name = recipe.name
        isBuiltIn = FilmRecipe.builtIns.contains { $0.id == recipe.id }
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: isBuiltIn ? "Built-in" : "My Recipes",
            image: .init(systemName: "film")
        )
    }
}

struct RecipeQuery: EntityStringQuery {
    @Dependency private var model: AppModel

    @MainActor
    func entities(for identifiers: [RecipeEntity.ID]) async throws -> [RecipeEntity] {
        model.availableRecipes
            .filter { identifiers.contains($0.id) }
            .map(RecipeEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [RecipeEntity] {
        model.availableRecipes
            .filter { $0.name.localizedStandardContains(string) }
            .map(RecipeEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [RecipeEntity] {
        model.availableRecipes.map(RecipeEntity.init)
    }
}

struct ApplyRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Granular Recipe"
    static let description = IntentDescription(
        "Gives images a film look with a Granular recipe, saved with the format, size and naming from Granular’s Output settings.",
        categoryName: "Images"
    )

    @Parameter(
        title: "Images",
        supportedContentTypes: [.jpeg, .heic, .png, .tiff],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var images: [IntentFile]

    @Parameter(
        title: "Recipe",
        description: "Leave empty to use the recipe that’s selected in Granular."
    )
    var recipe: RecipeEntity?

    @Parameter(
        title: "Output Folder",
        description: "Leave empty to use Granular’s Instant output folder.",
        supportedContentTypes: [.folder]
    )
    var folder: IntentFile?

    static var parameterSummary: some ParameterSummary {
        Summary("Apply \(\.$recipe) to \(\.$images)") {
            \.$folder
        }
    }

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        // A recipe that has since been deleted falls back to the one in use.
        let chosen = recipe.flatMap { entity in model.availableRecipes.first { $0.id == entity.id } }
            ?? model.recipe

        let destination = try outputFolder()
        let gainedFolderAccess = destination.startAccessingSecurityScopedResource()
        defer {
            if gainedFolderAccess { destination.stopAccessingSecurityScopedResource() }
        }
        guard AppModel.isExistingDirectory(destination) else {
            throw ShortcutError.folderUnavailable(destination.lastPathComponent)
        }

        let inputs = try ShortcutInputs(images)
        defer { inputs.cleanUp() }

        let outputs = try await model.processForShortcut(inputs.urls, recipe: chosen, destination: destination)
        return .result(value: outputs.map { url in
            IntentFile(fileURL: url, filename: url.lastPathComponent, type: UTType(filenameExtension: url.pathExtension))
        })
    }

    @MainActor
    private func outputFolder() throws -> URL {
        if let folder {
            guard let url = folder.fileURL else {
                throw ShortcutError.folderUnavailable(folder.filename)
            }
            return url
        }
        guard let dropOutputFolder = model.dropOutputFolder else {
            throw ShortcutError.noOutputFolder
        }
        return dropOutputFolder
    }
}

struct GetRecipesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Granular Recipes"
    static let description = IntentDescription(
        "Gets Granular’s built-in recipes and the ones you’ve saved.",
        categoryName: "Recipes"
    )

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[RecipeEntity]> {
        .result(value: model.availableRecipes.map(RecipeEntity.init))
    }
}

/// The images a shortcut hands over, as files Granular can read. Shortcuts
/// usually passes files it has already granted access to; anything else (a
/// photo from Photos, say) arrives as data and is written out for the run.
@MainActor
private struct ShortcutInputs {
    private(set) var urls: [URL] = []
    private var scopedURLs: [URL] = []
    private var temporaryFolder: URL?

    init(_ files: [IntentFile]) throws {
        for file in files {
            let name = file.fileURL?.lastPathComponent ?? file.filename
            guard AppModel.isSupportedImage(URL(fileURLWithPath: name)) else { continue }

            if let url = file.fileURL {
                let gainedAccess = url.startAccessingSecurityScopedResource()
                if FileManager.default.isReadableFile(atPath: url.path) {
                    if gainedAccess { scopedURLs.append(url) }
                    urls.append(url)
                    continue
                }
                if gainedAccess { url.stopAccessingSecurityScopedResource() }
            }

            if temporaryFolder == nil {
                try makeTemporaryFolder()
            }
            guard let folder = temporaryFolder else { continue }
            // Each file gets its own folder so two “IMG_0001.jpg”s can’t collide,
            // and the output keeps the original name.
            let copy = folder
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
                .appending(path: name)
            try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: copy)
            urls.append(copy)
        }
        guard !urls.isEmpty else {
            cleanUp()
            throw ShortcutError.noImages
        }
    }

    private mutating func makeTemporaryFolder() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Shortcuts-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        temporaryFolder = folder
    }

    func cleanUp() {
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        if let temporaryFolder {
            try? FileManager.default.removeItem(at: temporaryFolder)
        }
    }
}
