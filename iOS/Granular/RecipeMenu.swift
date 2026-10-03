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
            Button("Recipes…", systemImage: "square.stack") {
                darkroom.recipeSheet = .library
            }
            Picker("Recipe", selection: selection) {
                ForEach(listedRecipes) { recipe in
                    Text(recipe.name).tag(recipe.id)
                }
            }
            Section {
                Button("Save as Recipe…", systemImage: "plus") {
                    darkroom.recipeSheet = .save
                }
                if darkroom.canUpdateSelectedRecipe {
                    Button("Update “\(darkroom.currentRecipe.name)”", systemImage: "arrow.triangle.2.circlepath") {
                        withAnimation(.smooth) { darkroom.updateSelectedRecipe() }
                    }
                }
            }
            if darkroom.isRecipeModified {
                Section {
                    Button("Revert to \(darkroom.currentRecipe.name)", systemImage: "arrow.uturn.backward") {
                        withAnimation(.smooth) { darkroom.revertRecipe() }
                    }
                }
            }
        } label: {
            label()
        }
        // Laid out as written, wherever the menu opens, so Raw stays last.
        .menuOrder(.fixed)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: darkroom.selectedRecipeID)
        .accessibilityLabel("Recipe: \(darkroom.recipeDisplayName)")
    }

    /// Your own recipes first, then the built-ins from Soft 16 down to the
    /// blank slate.
    private var listedRecipes: [FilmRecipe] {
        let builtIns = FilmRecipe.builtIns.filter { $0.id != "raw" }.reversed()
            + FilmRecipe.builtIns.filter { $0.id == "raw" }
        return darkroom.savedRecipes + builtIns
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
