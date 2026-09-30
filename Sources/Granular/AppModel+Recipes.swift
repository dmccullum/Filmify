import AppKit
import GranularCore
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// Choosing, saving, editing and persisting recipes.
extension AppModel {
    /// Puts a recipe to use. Choosing one is a step on Edit ▸ Undo; the app's
    /// own choices, such as falling back after a deletion, aren't.
    func selectRecipe(_ recipe: FilmRecipe, recordingUndo: Bool = true) {
        guard !recordingUndo else {
            changeAdjustments("Choose Recipe") { selectRecipe(recipe, recordingUndo: false) }
            return
        }
        selectedRecipeID = recipe.id
        self.recipe = recipe
        persistRecipeSelection()
        schedulePreview()
    }

    func recipeDidChange() {
        persistRecipeSelection()
        schedulePreview()
    }

    /// Asks for a name and canister for the current settings.
    func beginSavingRecipe() {
        isSavingRecipe = true
    }

    /// The name offered when saving: the recipe being edited, if it's one of ours.
    var suggestedRecipeName: String {
        isSelectedRecipeCustom ? recipe.name : "My Recipe"
    }

    /// Saves the current settings as a new recipe and puts it to use.
    @discardableResult
    func saveCurrentAsRecipe(named proposedName: String, canister: String) -> FilmRecipe? {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        var recipe = recipe
        recipe.id = "custom-\(UUID().uuidString)"
        recipe.name = name
        recipe.canister = canister
        savedRecipes.append(recipe)
        persistRecipes()
        selectRecipe(recipe, recordingUndo: false)
        statusMessage = "Saved recipe “\(name)”"
        return recipe
    }

    func updateSelectedRecipe() {
        guard let index = savedRecipes.firstIndex(where: { $0.id == selectedRecipeID }) else { return }
        var updated = recipe
        updated.id = savedRecipes[index].id
        updated.name = savedRecipes[index].name
        updated.canister = savedRecipes[index].canister
        savedRecipes[index] = updated
        recipe = updated
        persistRecipes()
        persistRecipeSelection()
        statusMessage = "Updated recipe “\(updated.name)”"
    }

    func deleteSelectedRecipe() {
        guard let index = savedRecipes.firstIndex(where: { $0.id == selectedRecipeID }) else { return }
        let name = savedRecipes[index].name

        let alert = NSAlert()
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = "This recipe will be permanently deleted. This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        savedRecipes.remove(at: index)
        persistRecipes()
        selectRecipe(.classic35, recordingUndo: false)
        statusMessage = "Deleted recipe “\(name)”"
    }

    func renameRecipe(id: String, to proposedName: String) -> Bool {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !savedRecipes.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }),
              let index = savedRecipes.firstIndex(where: { $0.id == id }) else { return false }

        savedRecipes[index].name = name
        if selectedRecipeID == id {
            recipe.name = name
            persistRecipeSelection()
        }
        persistRecipes()
        statusMessage = "Renamed recipe to “\(name)”"
        return true
    }

    /// Packages a saved recipe in a canister from the library.
    func setCanister(_ canister: String, forRecipe id: String) {
        guard let index = savedRecipes.firstIndex(where: { $0.id == id }) else { return }
        savedRecipes[index].canister = canister
        if selectedRecipeID == id {
            recipe.canister = canister
            persistRecipeSelection()
        }
        persistRecipes()
    }

    func deleteRecipe(id: String) {
        guard let index = savedRecipes.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedRecipeID == id
        let name = savedRecipes[index].name
        savedRecipes.remove(at: index)
        persistRecipes()
        if wasSelected {
            selectRecipe(.classic35, recordingUndo: false)
        }
        statusMessage = "Deleted recipe “\(name)”"
    }

    func resetLightShaping() {
        recipe.lightShaping = currentRecipe.lightShaping
        schedulePreview()
    }

    func resetTone() {
        recipe.tone = currentRecipe.tone
        schedulePreview()
    }

    func resetLensBlur() {
        recipe.lensBlur = currentRecipe.lensBlur
        schedulePreview()
    }

    func resetDiffusion() {
        recipe.diffusion = currentRecipe.diffusion
        schedulePreview()
    }

    func resetHalation() {
        recipe.halation = currentRecipe.halation
        schedulePreview()
    }

    func resetLandscapeGlow() {
        recipe.landscapeGlow = currentRecipe.landscapeGlow
        schedulePreview()
    }

    func resetGrain() {
        recipe.grain = currentRecipe.grain
        schedulePreview()
    }

    func randomizeGrain() {
        changeAdjustments("New Grain Pattern") {
            recipe.grain.seed = UInt32.random(in: 1 ..< 1_000_003)
        }
    }

    func restoreRecipes() {
        guard let data = UserDefaults.standard.data(forKey: RecipeKey.saved),
              let decoded = try? JSONDecoder().decode([FilmRecipe].self, from: data) else { return }
        savedRecipes = decoded
    }

    func persistRecipes() {
        guard let data = try? JSONEncoder().encode(savedRecipes) else { return }
        UserDefaults.standard.set(data, forKey: RecipeKey.saved)
    }

    func restoreRecipeSelection() {
        let defaults = UserDefaults.standard
        guard let storedID = defaults.string(forKey: RecipeKey.selectedID),
              let selected = availableRecipes.first(where: { $0.id == storedID }) else {
            selectRecipe(.classic35)
            return
        }

        selectedRecipeID = selected.id
        if defaults.bool(forKey: RecipeKey.isModified),
           let data = defaults.data(forKey: RecipeKey.working),
           var working = try? JSONDecoder().decode(FilmRecipe.self, from: data) {
            // Keep the originating recipe identity so Reset and Update still work.
            working.id = selected.id
            working.name = selected.name
            recipe = working
        } else {
            recipe = selected
        }
        persistRecipeSelection()
    }

    func persistRecipeSelection() {
        let defaults = UserDefaults.standard
        defaults.set(selectedRecipeID, forKey: RecipeKey.selectedID)
        defaults.set(isRecipeModified, forKey: RecipeKey.isModified)
        if let data = try? JSONEncoder().encode(recipe) {
            defaults.set(data, forKey: RecipeKey.working)
        }
    }
}

enum RecipeKey {
    static let saved = "recipes.saved"
    static let selectedID = "recipes.selectedID"
    static let working = "recipes.working"
    static let isModified = "recipes.isModified"
}
