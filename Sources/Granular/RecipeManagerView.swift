import GranularCore
import SwiftUI

struct RecipeManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String?
    @State private var draftName = ""
    @State private var renameError: String?
    @State private var isConfirmingDelete = false
    @FocusState private var isEditingName: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 200)

                Divider()

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            footer
        }
        // Sized to fit under the toolbar of the fixed-height Instant window.
        .frame(width: 560, height: 320)
        .onAppear {
            selectedID = model.isSelectedRecipeCustom
                ? model.selectedRecipeID
                : model.savedRecipes.first?.id
            loadDraftName()
        }
        .onChange(of: selectedID) { _, _ in
            loadDraftName()
        }
        .onChange(of: isEditingName) { _, isEditing in
            if !isEditing {
                commitRename()
            }
        }
        .confirmationDialog(
            "Delete “\(selectedRecipe?.name ?? "")”?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Recipe", role: .destructive) {
                deleteSelectedRecipe()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Built-in recipes are unaffected. This can’t be undone.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selectedID) {
            Section("My Recipes") {
                ForEach(model.savedRecipes) { recipe in
                    HStack(spacing: 10) {
                        MiniCanister(name: recipe.name, height: 26)
                        Text(recipe.name)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if recipe.id == model.selectedRecipeID, !model.isRecipeModified {
                            Circle()
                                .fill(FilmBackPalette.signal)
                                .frame(width: 6, height: 6)
                                .accessibilityLabel("In use")
                        }
                    }
                    .tag(recipe.id)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let recipe = selectedRecipe {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    MiniCanister(name: draftName.isEmpty ? recipe.name : draftName, height: 54)

                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Recipe Name", text: $draftName)
                            .textFieldStyle(.plain)
                            .font(.title3.weight(.semibold))
                            .focused($isEditingName)
                            .onSubmit { isEditingName = false }
                        Text(renameError ?? (isInUse(recipe) ? "In use" : "Saved recipe"))
                            .font(.caption)
                            .foregroundStyle(renameError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    }

                    Spacer(minLength: 8)

                    if !isInUse(recipe) {
                        Button("Use Recipe") {
                            model.selectRecipe(recipe)
                        }
                        .controlSize(.small)
                    }
                }

                Divider()

                settings(for: recipe)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)
        } else if model.savedRecipes.isEmpty {
            ContentUnavailableView(
                "No Recipes Yet",
                systemImage: "film.stack",
                description: Text("Dial in a look, then use + to keep it as a recipe of your own.")
            )
        } else {
            ContentUnavailableView(
                "No Recipe Selected",
                systemImage: "film.stack",
                description: Text("Choose a recipe to rename it or put it to use.")
            )
        }
    }

    private func settings(for recipe: FilmRecipe) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                label("Color Stock")
                Text(recipe.tone.stock.name)
                    .gridCellColumns(3)
                    .lineLimit(1)
            }
            GridRow {
                label("Exposure")
                value(recipe.tone.exposure.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false))))
                label("Vignette")
                value(recipe.lightShaping.amountStops)
            }
            GridRow {
                label("Lens Blur")
                value(recipe.lensBlur.amount)
                label("Diffusion")
                value(recipe.diffusion.amount)
            }
            GridRow {
                label("Halation")
                value(recipe.halation.amount)
                label("Landscape Glow")
                value(recipe.landscapeGlow.amount)
            }
            GridRow {
                label("Grain")
                value(recipe.grain.amount)
            }
        }
        .font(.callout)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private func value(_ amount: Double) -> some View {
        value(amount.formatted(.number.precision(.fractionLength(2))))
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .frame(minWidth: 44, alignment: .trailing)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            Button {
                model.saveCurrentAsRecipe()
                selectedID = model.isSelectedRecipeCustom ? model.selectedRecipeID : selectedID
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.borderless)
            .help("Save the current settings as a new recipe")
            .accessibilityLabel("Save New Recipe")

            Button {
                isConfirmingDelete = true
            } label: {
                Image(systemName: "minus")
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(selectedRecipe == nil)
            .help("Delete the selected recipe")
            .accessibilityLabel("Delete Recipe")

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
    }

    // MARK: Actions

    private var selectedRecipe: FilmRecipe? {
        guard let selectedID else { return nil }
        return model.savedRecipes.first { $0.id == selectedID }
    }

    private func isInUse(_ recipe: FilmRecipe) -> Bool {
        recipe.id == model.selectedRecipeID && !model.isRecipeModified
    }

    private func loadDraftName() {
        draftName = selectedRecipe?.name ?? ""
        renameError = nil
    }

    private func commitRename() {
        guard let selectedID, let recipe = selectedRecipe else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != recipe.name else {
            loadDraftName()
            return
        }
        if model.renameRecipe(id: selectedID, to: name) {
            loadDraftName()
        } else {
            renameError = "Use a name that isn’t empty or already taken."
        }
    }

    private func deleteSelectedRecipe() {
        guard let selectedID else { return }
        model.deleteRecipe(id: selectedID)
        self.selectedID = model.savedRecipes.first?.id
    }
}

/// A saved recipe's bulk-loaded canister, with its name on the tape, as a small glyph.
private struct MiniCanister: View {
    let name: String
    let height: CGFloat

    var body: some View {
        FilmCanisterView(style: .bulk(name), recipeName: name, height: height)
            .frame(width: CanisterStyle.designBodyWidth * height / 320 + 2, height: height)
            .accessibilityHidden(true)
    }
}
