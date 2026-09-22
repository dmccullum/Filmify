import GranularCore
import SwiftUI

struct RecipeManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String?
    @State private var draftName = ""
    @State private var renameError: String?
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                recipeList
                    .frame(width: 220)

                Divider()

                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(22)
            }

            Divider()

            HStack {
                Button("Save New Recipe…", systemImage: "plus") {
                    model.saveCurrentAsRecipe()
                    selectedID = model.selectedRecipeID
                    loadDraftName()
                }

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 560, height: 360)
        .onAppear {
            selectedID = model.isSelectedRecipeCustom
                ? model.selectedRecipeID
                : model.savedRecipes.first?.id
            loadDraftName()
        }
        .confirmationDialog(
            "Delete this recipe?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Recipe", role: .destructive) {
                deleteSelectedRecipe()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Built-in recipes are unaffected. This cannot be undone.")
        }
    }

    private var recipeList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("My Recipes")
                    .font(.headline)
                Spacer()
                Text("\(model.savedRecipes.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Divider()

            if model.savedRecipes.isEmpty {
                ContentUnavailableView(
                    "No Recipes Yet",
                    systemImage: "camera.filters",
                    description: Text("Save your current adjustments to create your first recipe.")
                )
            } else {
                List(model.savedRecipes) { recipe in
                    Button {
                        selectedID = recipe.id
                        loadDraftName()
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.secondary)
                            Text(recipe.name)
                                .lineLimit(1)
                            Spacer()
                            if recipe.id == selectedID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
        .background(.bar)
    }

    @ViewBuilder
    private var editor: some View {
        if let recipe = selectedRecipe {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recipe Details")
                    .font(.title2.weight(.semibold))

                TextField("Name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(renameSelectedRecipe)

                if let renameError {
                    Text(renameError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Color Stock", value: recipe.tone.stock.name)
                    LabeledContent("Exposure", value: recipe.tone.exposure.formatted(.number.precision(.fractionLength(1))))
                    LabeledContent("Vignette", value: recipe.lightShaping.amountStops.formatted(.number.precision(.fractionLength(2))))
                    LabeledContent("Lens Blur", value: recipe.lensBlur.amount.formatted(.number.precision(.fractionLength(2))))
                    LabeledContent("Diffusion", value: recipe.diffusion.amount.formatted(.number.precision(.fractionLength(2))))
                    LabeledContent("Halation", value: recipe.halation.amount.formatted(.number.precision(.fractionLength(2))))
                    LabeledContent("Landscape Glow", value: recipe.landscapeGlow.amount.formatted(.number.precision(.fractionLength(2))))
                    LabeledContent("Grain", value: recipe.grain.amount.formatted(.number.precision(.fractionLength(2))))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                HStack {
                    Button("Rename") { renameSelectedRecipe() }
                        .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    Button("Delete…", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Select a Recipe",
                systemImage: "list.bullet",
                description: Text("User-created recipes can be renamed and deleted here.")
            )
        }
    }

    private var selectedRecipe: FilmRecipe? {
        guard let selectedID else { return nil }
        return model.savedRecipes.first { $0.id == selectedID }
    }

    private func loadDraftName() {
        draftName = selectedRecipe?.name ?? ""
        renameError = nil
    }

    private func renameSelectedRecipe() {
        guard let selectedID else { return }
        if model.renameRecipe(id: selectedID, to: draftName) {
            renameError = nil
            loadDraftName()
        } else {
            renameError = "Use a non-empty, unique name."
        }
    }

    private func deleteSelectedRecipe() {
        guard let selectedID else { return }
        model.deleteRecipe(id: selectedID)
        self.selectedID = model.savedRecipes.first?.id
        loadDraftName()
    }
}
