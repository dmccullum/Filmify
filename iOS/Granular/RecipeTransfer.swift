import CoreTransferable
import GranularCore
import UniformTypeIdentifiers

extension UTType {
    /// A recipe saved as a file, declared in Info.plist.
    static let granularRecipe = UTType(exportedAs: RecipeFile.typeIdentifier, conformingTo: .json)
}

/// A recipe as a file to share, named for the recipe when it arrives in
/// Files, Messages or AirDrop.
struct RecipeDocument: Transferable {
    let recipe: FilmRecipe

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .granularRecipe) { document in
            let folder = FileManager.default.temporaryDirectory
                .appending(path: "Shared-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: RecipeFile.fileName(for: document.recipe))
            try RecipeFile(recipe: document.recipe).encoded().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
