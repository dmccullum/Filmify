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
        schedulePreview()
        // A slider drag changes the recipe on every tick; save once it rests.
        recipeSaveTask?.cancel()
        recipeSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persistRecipeSelection()
        }
    }

    /// Whether a recipe is the look in use, exactly as it was saved.
    func isInUse(_ recipe: FilmRecipe) -> Bool {
        !isRecipeModified && recipe.id == selectedRecipeID
    }

    func isSavedRecipe(_ id: String) -> Bool {
        savedRecipes.contains { $0.id == id }
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
        recipe.id = Self.newRecipeID()
        recipe.name = name
        recipe.canister = canister
        changeRecipes("Save Recipe") {
            savedRecipes.append(recipe)
            persistRecipes()
            selectRecipe(recipe, recordingUndo: false)
        }
        statusMessage = "Saved recipe “\(name)”"
        return recipe
    }

    /// Saves the current edits into the recipe they started from.
    func updateSelectedRecipe() {
        guard let index = savedRecipes.firstIndex(where: { $0.id == selectedRecipeID }) else { return }
        let updated = savedRecipes[index].applyingAdjustments(of: recipe)
        changeRecipes("Update Recipe") {
            savedRecipes[index] = updated
            recipe = updated
            persistRecipes()
            persistRecipeSelection()
        }
        statusMessage = "Updated recipe “\(updated.name)”"
    }

    /// Asks, in the window the request came from, before deleting the
    /// recipe in use. Only saved recipes can be deleted.
    func requestDeletingCurrentRecipe() {
        requestDeletingRecipe(id: selectedRecipeID)
    }

    func requestDeletingRecipe(id: String, in window: RecipeWindow? = nil) {
        guard let recipe = savedRecipes.first(where: { $0.id == id }) else { return }
        recipeDeletionRequest = RecipeDeletionRequest(recipe: recipe, window: window ?? activeRecipeWindow)
    }

    /// Deletes a saved recipe. If it was in use, the look stays as it is and
    /// simply no longer belongs to a saved recipe.
    func deleteRecipe(id: String, in window: RecipeWindow? = nil) {
        guard let index = savedRecipes.firstIndex(where: { $0.id == id }) else { return }
        let name = savedRecipes[index].name
        changeRecipes("Delete Recipe", in: window) {
            savedRecipes.remove(at: index)
            persistRecipes()
            if selectedRecipeID == id {
                selectedRecipeID = FilmRecipe.classic35.id
                recipe = FilmRecipe.classic35.applyingAdjustments(of: recipe)
                persistRecipeSelection()
            }
        }
        statusMessage = "Deleted recipe “\(name)”"
    }

    func renameRecipe(id: String, to proposedName: String) -> Bool {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !savedRecipes.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }),
              let index = savedRecipes.firstIndex(where: { $0.id == id }) else { return false }

        changeRecipes("Rename Recipe") {
            savedRecipes[index].name = name
            if selectedRecipeID == id {
                recipe.name = name
                persistRecipeSelection()
            }
            persistRecipes()
        }
        statusMessage = "Renamed recipe to “\(name)”"
        return true
    }

    /// Packages a saved recipe in a canister from the library.
    func setCanister(_ canister: String, forRecipe id: String) {
        guard let index = savedRecipes.firstIndex(where: { $0.id == id }) else { return }
        changeRecipes("Change Canister") {
            savedRecipes[index].canister = canister
            if selectedRecipeID == id {
                recipe.canister = canister
                persistRecipeSelection()
            }
            persistRecipes()
        }
    }

    /// Saves a copy of any recipe, built-in or saved, just after it in the
    /// list, in the same canister.
    @discardableResult
    func duplicateRecipe(id: String) -> FilmRecipe? {
        guard let copy = makeDuplicate(of: id) else { return nil }
        changeRecipes("Duplicate Recipe") {
            savedRecipes.insert(copy, at: duplicateIndex(for: id))
            persistRecipes()
        }
        statusMessage = "Duplicated as “\(copy.name)”"
        return copy
    }

    /// Duplicates the recipe in use and carries on with the copy, edits and
    /// all, so Update saves them there instead of into the original.
    func duplicateCurrentRecipe() {
        let id = selectedRecipeID
        guard let copy = makeDuplicate(of: id) else { return }
        changeRecipes("Duplicate Recipe") {
            savedRecipes.insert(copy, at: duplicateIndex(for: id))
            persistRecipes()
            selectedRecipeID = copy.id
            recipe = copy.applyingAdjustments(of: recipe)
            persistRecipeSelection()
        }
        recipeLibrarySelection = copy.id
        statusMessage = "Duplicated as “\(copy.name)”"
    }

    private func makeDuplicate(of id: String) -> FilmRecipe? {
        guard let original = availableRecipes.first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = Self.newRecipeID()
        copy.name = FilmRecipe.duplicateName(for: original.name, among: availableRecipes.map(\.name))
        copy.canister = CanisterDesign.resolved(for: original).id
        return copy
    }

    /// Just after the original if it's saved; at the end for a built-in.
    private func duplicateIndex(for id: String) -> Int {
        savedRecipes.firstIndex(where: { $0.id == id }).map { $0 + 1 } ?? savedRecipes.count
    }

    /// Reorders the saved recipes, which every recipe list follows.
    func moveSavedRecipes(fromOffsets source: IndexSet, toOffset destination: Int) {
        changeRecipes("Move Recipe") {
            savedRecipes.move(fromOffsets: source, toOffset: destination)
            persistRecipes()
        }
    }

    /// Opens the Recipe Library window, showing a recipe if one is given.
    func showRecipeLibrary(selecting id: String? = nil) {
        if let id {
            recipeLibrarySelection = id
        }
        showRecipeManager = true
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

    private static func newRecipeID() -> String {
        "custom-\(UUID().uuidString)"
    }
}

// MARK: - Undo

/// What Edit ▸ Undo puts back for a change to the recipe library: the saved
/// recipes, and which one is in use.
struct RecipeLibraryState: Equatable {
    var savedRecipes: [FilmRecipe]
    var selectedRecipeID: String
}

/// The two windows a recipe change can be made from, each with its own
/// Edit ▸ Undo and its own place for a confirmation to appear.
enum RecipeWindow {
    case main
    case library
}

/// A deletion waiting on a yes, shown as a sheet on the window it came from.
struct RecipeDeletionRequest: Identifiable {
    let recipe: FilmRecipe
    let window: RecipeWindow

    var id: String { recipe.id }
}

struct RecipeLibraryAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension AppModel {
    var recipeLibraryState: RecipeLibraryState {
        RecipeLibraryState(savedRecipes: savedRecipes, selectedRecipeID: selectedRecipeID)
    }

    /// Makes a change to the saved recipes as one step on Edit ▸ Undo, in
    /// the window it was made from: the Recipe Library keeps its own steps,
    /// everything else joins the main window's.
    func changeRecipes(_ actionName: String, in window: RecipeWindow? = nil, change: () -> Void) {
        let libraryUndoManager = (window ?? activeRecipeWindow) == .library ? recipeLibraryWindow?.undoManager : nil
        guard let libraryUndoManager else {
            performUndoable(actionName, capture: \.recipeLibraryState, restore: { model, state in
                model.restoreRecipeLibrary(state)
            }, change: change)
            return
        }

        let before = recipeLibraryState
        change()
        guard recipeLibraryState != before else { return }
        registerRecipeUndo(actionName, restoring: before, on: libraryUndoManager)
    }

    /// Records a step on the Recipe Library's own undo manager. Undoing it
    /// records the state it replaces in turn, which is what Redo puts back.
    private func registerRecipeUndo(_ actionName: String, restoring state: RecipeLibraryState, on manager: UndoManager) {
        manager.registerUndo(withTarget: self) { model in
            model.registerRecipeUndo(actionName, restoring: model.recipeLibraryState, on: manager)
            model.restoreRecipeLibrary(state)
        }
        manager.setActionName(actionName)
    }

    /// Puts the saved recipes and the choice of recipe back, keeping the look
    /// in use as it is now.
    func restoreRecipeLibrary(_ state: RecipeLibraryState) {
        savedRecipes = state.savedRecipes
        persistRecipes()
        let identity = availableRecipes.first { $0.id == state.selectedRecipeID } ?? .classic35
        selectedRecipeID = identity.id
        recipe = identity.applyingAdjustments(of: recipe)
        persistRecipeSelection()
    }

    // MARK: The library window

    /// Keeps hold of the Recipe Library's window, for its undo manager and
    /// for sheets, and has it remember its frame.
    func attachRecipeLibraryWindow(_ window: NSWindow) {
        guard recipeLibraryWindow !== window else { return }
        recipeLibraryWindow = window
        window.setFrameUsingName(Self.recipeLibraryFrameName)
        window.setFrameAutosaveName(Self.recipeLibraryFrameName)
    }

    private static let recipeLibraryFrameName = "RecipeLibrary"

    func isRecipeLibraryWindow(_ window: NSWindow) -> Bool {
        window === recipeLibraryWindow
            || window.identifier?.rawValue.contains(RecipeLibraryView.windowID) == true
    }

    /// The window a menu command or shortcut is working in: the Recipe
    /// Library while it, or a sheet or popover of its own, has focus.
    var activeRecipeWindow: RecipeWindow {
        guard let key = NSApp.keyWindow else { return .main }
        let window = key.sheetParent ?? key.parent ?? key
        return isRecipeLibraryWindow(window) ? .library : .main
    }
}
