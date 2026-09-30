import SwiftUI

/// The Recipe menu.
struct RecipeCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Recipe") {
            ForEach(model.availableRecipes) { recipe in
                Button(recipe.name) {
                    model.selectRecipe(recipe)
                }
            }

            Divider()

            Button("Save New Recipe…") {
                model.beginSavingRecipe()
            }
            .disabled(model.operationMode != .edit)

            Button("Manage Recipes…") {
                model.showRecipeManager = true
            }

            if model.isSelectedRecipeCustom {
                Button("Update Current Recipe") {
                    model.updateSelectedRecipe()
                }
                Button("Delete Current Recipe…", role: .destructive) {
                    model.deleteSelectedRecipe()
                }
            }

            Divider()

            Button("New Grain Pattern") {
                model.randomizeGrain()
            }
        }
    }
}
