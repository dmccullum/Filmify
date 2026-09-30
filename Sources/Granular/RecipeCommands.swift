import GranularCore
import SwiftUI

/// The Recipe menu.
struct RecipeCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    var body: some Commands {
        CommandMenu("Recipe") {
            Section("Built-in") {
                recipeItems(FilmRecipe.builtIns, startingAt: 0)
            }
            if !model.savedRecipes.isEmpty {
                Section("My Recipes") {
                    recipeItems(model.savedRecipes, startingAt: FilmRecipe.builtIns.count)
                }
            }

            Divider()

            Button("Save New Recipe…") {
                model.beginSavingRecipe()
            }
            .disabled(model.operationMode != .edit)

            if model.isSelectedRecipeCustom {
                Button("Update Current Recipe") {
                    model.updateSelectedRecipe()
                }
                .disabled(!model.isRecipeModified)
            }

            Button("Duplicate Current Recipe") {
                model.duplicateCurrentRecipe()
            }

            if model.isSelectedRecipeCustom {
                Button("Delete Current Recipe…", role: .destructive) {
                    model.requestDeletingCurrentRecipe()
                }
            }

            Divider()

            Button("Import Recipe…") {
                model.chooseRecipesToImport(then: openLibrary)
            }

            Button("Recipe Library…") {
                openLibrary()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Divider()

            Button("New Grain Pattern") {
                model.randomizeGrain()
            }
        }
    }

    /// Each recipe, checked while it's the look in use; the first nine in
    /// list order answer to ⌥⌘1 through ⌥⌘9.
    private func recipeItems(_ recipes: [FilmRecipe], startingAt offset: Int) -> some View {
        ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
            Toggle(recipe.name, isOn: Binding(
                get: { model.isInUse(recipe) },
                set: { _ in model.selectRecipe(recipe) }
            ))
            .keyboardShortcut(Self.shortcut(forPosition: offset + index))
        }
    }

    private static func shortcut(forPosition position: Int) -> KeyboardShortcut? {
        guard position < 9 else { return nil }
        return KeyboardShortcut(KeyEquivalent(Character("\(position + 1)")), modifiers: [.command, .option])
    }

    private func openLibrary() {
        openWindow(id: RecipeLibraryView.windowID)
    }
}
