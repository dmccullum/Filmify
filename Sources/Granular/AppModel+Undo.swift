import AppKit
import GranularCore
import SwiftUI

/// What Edit ▸ Undo steps through for the adjustments: the look itself, and
/// the recipe it started from.
struct RecipeEditState: Equatable {
    var recipe: FilmRecipe
    var selectedRecipeID: String
}

/// A run of changes that make up a single undo step, such as the ticks of
/// one slider drag.
struct OpenUndoStep {
    let key: AnyHashable
    let actionName: String
}

// Undo and redo for the adjustments.
//
// Everything is recorded on the main window's own undo manager, so the
// standard Edit ▸ Undo and Redo items name each step, and text being typed in
// a field still undoes as text, ahead of the adjustments.
extension AppModel {
    var editState: RecipeEditState {
        RecipeEditState(recipe: recipe, selectedRecipeID: selectedRecipeID)
    }

    /// Changes the adjustments as one step on Edit ▸ Undo, named for what
    /// changed (“Undo Exposure”). Changes sharing a `coalescingKey` — the ticks
    /// of one slider drag, a run of arrow-key nudges — join the step already
    /// open for that key instead of starting their own.
    func changeAdjustments(_ actionName: String, coalescingKey: AnyHashable? = nil, _ change: () -> Void) {
        // A change made inside another belongs to the outer one's step.
        guard adjustmentChangeDepth == 0 else {
            change()
            return
        }

        let before = editState
        adjustmentChangeDepth += 1
        change()
        adjustmentChangeDepth -= 1
        guard editState != before else { return }

        if let coalescingKey, continuesOpenUndoStep(coalescingKey, actionName: actionName) {
            // The open step already puts back the state from before the run.
        } else {
            registerUndo(actionName, restoring: before, capture: \.editState) { model, state in
                model.applyEditState(state)
            }
            openUndoStep = coalescingKey.map { OpenUndoStep(key: $0, actionName: actionName) }
        }
        recipeDidChange()
    }

    /// Ends a run of changes, so the next one starts a step of its own. With a
    /// key, only that run ends.
    func endCoalescedChanges(_ key: AnyHashable? = nil) {
        guard key == nil || openUndoStep?.key == key else { return }
        openUndoStep = nil
    }

    /// Makes a change as one step on Edit ▸ Undo, for state beyond the
    /// adjustments. `capture` reads the state the step covers and `restore`
    /// puts it back, persisting as needed. The recipe library can use this for
    /// renames, deletions and reordering:
    ///
    ///     performUndoable("Delete Recipe", capture: \.savedRecipes) { model, recipes in
    ///         model.savedRecipes = recipes
    ///         model.persistRecipes()
    ///     } change: {
    ///         savedRecipes.remove(at: index)
    ///         persistRecipes()
    ///     }
    func performUndoable<State: Equatable>(
        _ actionName: String,
        capture: @escaping (AppModel) -> State,
        restore: @escaping (AppModel, State) -> Void,
        change: () -> Void
    ) {
        let before = capture(self)
        change()
        guard capture(self) != before else { return }
        openUndoStep = nil
        registerUndo(actionName, restoring: before, capture: capture, restore: restore)
    }

    /// Records one named step that puts some state back as it was. Undoing it
    /// records the state it replaces in turn, which is what Redo puts back.
    func registerUndo<State>(
        _ actionName: String,
        restoring state: State,
        capture: @escaping (AppModel) -> State,
        restore: @escaping (AppModel, State) -> Void
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.openUndoStep = nil
            model.registerUndo(actionName, restoring: capture(model), capture: capture, restore: restore)
            restore(model, state)
        }
        undoManager.setActionName(actionName)
    }

    /// Puts the adjustments and recipe choice back. The recipe keeps its
    /// current name and canister, which may have changed since.
    func applyEditState(_ state: RecipeEditState) {
        let identity = availableRecipes.first { $0.id == state.selectedRecipeID } ?? state.recipe
        selectedRecipeID = state.selectedRecipeID
        recipe = identity.applyingAdjustments(of: state.recipe)
        recipeDidChange()
    }

    private func continuesOpenUndoStep(_ key: AnyHashable, actionName: String) -> Bool {
        guard let openUndoStep, openUndoStep.key == key,
              // A fresh press is a fresh step, even on the same control.
              NSApp.currentEvent?.type != .leftMouseDown,
              // Something else, such as typing, may have been recorded since.
              undoManager?.undoActionName == actionName else { return false }
        return true
    }
}

/// Hands the model the main window's undo manager, so changes from anywhere —
/// the inspector, the Recipe menu, Instant mode's canister — land on that
/// window's Edit ▸ Undo.
private struct AdjustmentUndoConnection: ViewModifier {
    @Environment(\.undoManager) private var undoManager
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .onChange(of: undoManager, initial: true) { _, undoManager in
                model.undoManager = undoManager
            }
    }
}

extension View {
    /// Records the model's adjustments on this window's Edit ▸ Undo.
    func recordingAdjustmentUndo(for model: AppModel) -> some View {
        modifier(AdjustmentUndoConnection(model: model))
    }
}
