import Foundation

public extension FilmRecipe {
    /// This recipe with another's look — every adjustment, grain pattern
    /// included — while keeping its own identity, name and canister, so Reset
    /// and Update still refer to the recipe it came from.
    func applyingAdjustments(of source: FilmRecipe) -> FilmRecipe {
        var recipe = source
        recipe.id = id
        recipe.name = name
        recipe.canister = canister
        return recipe
    }

    /// Whether two recipes would render the same, whatever they're called.
    func hasSameAdjustments(as other: FilmRecipe) -> Bool {
        applyingAdjustments(of: other) == self
    }
}
