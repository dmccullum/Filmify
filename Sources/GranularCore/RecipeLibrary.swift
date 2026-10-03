import Foundation

/// The recipes a person has made, and the operations that keep them tidy:
/// saving, updating, renaming, duplicating, deleting, reordering and importing.
/// Pure data, so every rule can be tested without a screen or user defaults.
public struct RecipeLibrary: Equatable, Sendable {
    public var saved: [FilmRecipe]

    public init(saved: [FilmRecipe] = []) {
        self.saved = saved
    }

    /// Built-in recipes first, then the saved ones in their order.
    public var all: [FilmRecipe] { FilmRecipe.builtIns + saved }

    public static func newID() -> String {
        "custom-\(UUID().uuidString)"
    }

    public func contains(savedID id: String) -> Bool {
        saved.contains { $0.id == id }
    }

    /// Saves a look as a new recipe under a name no other recipe has. Returns
    /// it, or nil when the name is empty.
    @discardableResult
    public mutating func save(_ look: FilmRecipe, named proposedName: String, canister: String?) -> FilmRecipe? {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var recipe = look
        recipe.id = Self.newID()
        recipe.name = FilmRecipe.uniqueName(name, among: all.map(\.name))
        recipe.canister = canister
        saved.append(recipe)
        return recipe
    }

    /// Writes a look into the saved recipe it came from, keeping the recipe's
    /// identity, name and canister. Returns the updated recipe.
    @discardableResult
    public mutating func update(id: String, with look: FilmRecipe) -> FilmRecipe? {
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return nil }
        saved[index] = saved[index].applyingAdjustments(of: look)
        return saved[index]
    }

    /// Renames a saved recipe. False for an empty name, or one another recipe
    /// already has, whatever its case.
    @discardableResult
    public mutating func rename(id: String, to proposedName: String) -> Bool {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = saved.firstIndex(where: { $0.id == id }),
              !all.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return false }
        saved[index].name = name
        return true
    }

    public mutating func setCanister(_ canister: String?, for id: String) {
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[index].canister = canister
    }

    /// Saves a copy of any recipe just after it, or at the end for a built-in.
    /// The caller names the canister, since the designs live outside Core.
    @discardableResult
    public mutating func duplicate(id: String, canister: String?) -> FilmRecipe? {
        guard let original = all.first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = Self.newID()
        copy.name = FilmRecipe.duplicateName(for: original.name, among: all.map(\.name))
        copy.canister = canister
        let index = saved.firstIndex(where: { $0.id == id }).map { $0 + 1 } ?? saved.count
        saved.insert(copy, at: index)
        return copy
    }

    public mutating func delete(id: String) {
        saved.removeAll { $0.id == id }
    }

    /// Moves recipes the way `Array.move(fromOffsets:toOffset:)` does.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.filter { saved.indices.contains($0) }.map { saved[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) where saved.indices.contains(index) {
            saved.remove(at: index)
        }
        saved.insert(contentsOf: moving, at: min(max(destination - before, 0), saved.count))
    }

    /// Adds recipes from files, each with an identity and name of its own.
    /// Returns what was added.
    @discardableResult
    public mutating func importing(_ recipes: [FilmRecipe]) -> [FilmRecipe] {
        var names = all.map(\.name)
        var added: [FilmRecipe] = []
        for var recipe in recipes {
            recipe.id = Self.newID()
            recipe.name = FilmRecipe.uniqueName(recipe.name, among: names)
            names.append(recipe.name)
            added.append(recipe)
        }
        saved.append(contentsOf: added)
        return added
    }
}
