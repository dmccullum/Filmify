import GranularCore
import SwiftUI

/// The recipes to load, opened from the canister in Instant and from the
/// recipe button in Edit. With edits made, the recipe they came from can be
/// gone back to.
struct RecipeMenu<Label: View>: View {
    @Environment(Darkroom.self) private var darkroom
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            if darkroom.isRecipeModified {
                Button("Revert to \(darkroom.currentRecipe.name)", systemImage: "arrow.uturn.backward") {
                    withAnimation(.smooth) { darkroom.revertRecipe() }
                }
            }
            Section {
                if darkroom.canUpdateSelectedRecipe {
                    Button("Update “\(darkroom.currentRecipe.name)”", systemImage: "arrow.triangle.2.circlepath") {
                        withAnimation(.smooth) { darkroom.updateSelectedRecipe() }
                    }
                }
                Button("Save as Recipe…", systemImage: "plus") {
                    darkroom.recipeSheet = .save
                }
            }
            Picker("Recipe", selection: selection) {
                ForEach(darkroom.availableRecipes) { recipe in
                    Text(recipe.name).tag(recipe.id)
                }
            }
            Button("Recipes…", systemImage: "square.stack") {
                darkroom.recipeSheet = .library
            }
        } label: {
            label()
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: darkroom.selectedRecipeID)
        .accessibilityLabel("Recipe: \(darkroom.recipeDisplayName)")
    }

    /// No recipe is ticked while the look has been edited away from it.
    private var selection: Binding<String> {
        Binding {
            darkroom.isRecipeModified ? "" : darkroom.selectedRecipeID
        } set: { id in
            guard let recipe = darkroom.availableRecipes.first(where: { $0.id == id }) else { return }
            withAnimation(.smooth) { darkroom.selectRecipe(recipe) }
        }
    }
}
