import Foundation

/// A recipe as a file of its own, for keeping or sharing outside the app.
///
/// The file is JSON: a format version beside the recipe itself.
///
///     { "version": 1, "recipe": { "name": "Longmarch", "canister": "ember", … } }
///
/// Reading is forgiving, because files outlive the version that wrote them:
/// a missing version reads as the first, a missing name comes from the file
/// name, missing groups of adjustments take their defaults, and a bare recipe
/// with no envelope at all still loads. A file from a later version is read
/// as far as it can be, and only turned away if that fails.
public struct RecipeFile: Equatable, Sendable {
    public static let typeIdentifier = "com.danielmccullum.granular.recipe"
    public static let fileExtension = "granularrecipe"
    public static let currentVersion = 1

    public var version: Int
    public var recipe: FilmRecipe

    public init(recipe: FilmRecipe, version: Int = Self.currentVersion) {
        self.version = version
        self.recipe = recipe
    }

    public static func isRecipeFile(_ url: URL) -> Bool {
        url.pathExtension.localizedCaseInsensitiveCompare(fileExtension) == .orderedSame
    }

    /// The file name a recipe is saved under, with anything the Finder
    /// wouldn't take in a name swapped out.
    public static func fileName(for recipe: FilmRecipe) -> String {
        let name = recipe.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = name.isEmpty || name.hasPrefix(".") ? "Recipe" : name
        return "\(base).\(fileExtension)"
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope(version: version, recipe: recipe))
    }

    /// Reads a recipe file. `fallbackName` names a recipe that doesn't carry
    /// its own name, usually the file's name.
    public static func decode(_ data: Data, fallbackName: String) throws -> RecipeFile {
        let decoder = JSONDecoder()
        decoder.userInfo[.recipeFileFallbackName] = fallbackName
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch let error as RecipeFileError {
            throw error
        } catch {
            // Say so when a later version wrote something this one can't read.
            if let version = try? JSONDecoder().decode(VersionProbe.self, from: data).version,
               version > currentVersion {
                throw RecipeFileError.newerVersion(version)
            }
            throw RecipeFileError.unreadable
        }
        return RecipeFile(recipe: envelope.recipe, version: envelope.version)
    }

    private struct VersionProbe: Decodable {
        let version: Int
    }

    private struct Envelope: Codable {
        let version: Int
        let recipe: FilmRecipe

        private enum CodingKeys: String, CodingKey {
            case version
            case recipe
        }

        init(version: Int, recipe: FilmRecipe) {
            self.version = version
            self.recipe = recipe
        }

        init(from decoder: Decoder) throws {
            let fallbackName = decoder.userInfo[.recipeFileFallbackName] as? String ?? "Recipe"
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1

            let recipeContainer: KeyedDecodingContainer<FilmRecipe.CodingKeys>
            if container.contains(.recipe) {
                recipeContainer = try container.nestedContainer(keyedBy: FilmRecipe.CodingKeys.self, forKey: .recipe)
            } else {
                // A bare recipe, as the app keeps them itself.
                recipeContainer = try decoder.container(keyedBy: FilmRecipe.CodingKeys.self)
                let adjustmentKeys: [FilmRecipe.CodingKeys] = [
                    .tone, .lightShaping, .lensBlur, .diffusion, .halation, .landscapeGlow, .grain
                ]
                guard adjustmentKeys.contains(where: recipeContainer.contains) else {
                    throw RecipeFileError.unreadable
                }
            }

            let name = (try recipeContainer.decodeIfPresent(String.self, forKey: .name))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            recipe = try FilmRecipe(
                recipeContainer,
                id: try recipeContainer.decodeIfPresent(String.self, forKey: .id) ?? "",
                name: name.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
            )
        }
    }
}

public enum RecipeFileError: LocalizedError, Equatable {
    case unreadable
    case newerVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            "The file isn’t a Granular recipe, or it’s damaged."
        case .newerVersion:
            "The recipe was saved by a newer version of Granular. Update Granular to open it."
        }
    }
}

extension CodingUserInfoKey {
    static let recipeFileFallbackName = CodingUserInfoKey(rawValue: "recipeFileFallbackName")!
}
