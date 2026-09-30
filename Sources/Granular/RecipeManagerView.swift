import GranularCore
import SwiftUI

struct RecipeManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String?
    @State private var draftName = ""
    @State private var renameError: String?
    @State private var isConfirmingDelete = false
    @State private var isChoosingCanister = false
    @State private var isSavingRecipe = false
    @State private var isHoveringCanister = false
    @State private var isHoveringName = false
    @State private var nameSavedAt: Date?
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
        .sheet(isPresented: $isSavingRecipe) {
            SaveRecipeSheet { selectedID = $0.id }
                .environment(model)
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
                        MiniCanister(recipe: recipe, height: 26)
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
                    Button {
                        isChoosingCanister = true
                    } label: {
                        MiniCanister(recipe: previewRecipe(recipe), height: 54)
                            .padding(6)
                            .background(
                                .quaternary.opacity(isHoveringCanister ? 0.8 : 0.35),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "paintbrush.pointed.fill")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 17, height: 17)
                                    .background(Color.accentColor, in: Circle())
                                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                                    .offset(x: 5, y: 5)
                            }
                            .scaleEffect(isHoveringCanister ? 1.04 : 1)
                            .animation(.easeOut(duration: 0.12), value: isHoveringCanister)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringCanister = $0 }
                    .help("Choose a canister for this recipe")
                    .accessibilityLabel("Canister: \(CanisterDesign.resolved(for: recipe).name)")
                    .popover(isPresented: $isChoosingCanister, arrowEdge: .bottom) {
                        CanisterPicker(recipe: previewRecipe(recipe)) { design in
                            model.setCanister(design.id, forRecipe: recipe.id)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        nameField
                        nameStatus(for: recipe)
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

    /// The recipe name, which reads as a title at rest but shows a pencil and
    /// a hover highlight, and becomes a proper field while it's being edited.
    private var nameField: some View {
        HStack(spacing: 6) {
            TextField("Recipe Name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .focused($isEditingName)
                .onSubmit { isEditingName = false }
                .onExitCommand {
                    loadDraftName()
                    isEditingName = false
                }
            if !isEditingName {
                Image(systemName: "pencil")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .opacity(isHoveringName ? 1 : 0.55)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isEditingName
                      ? AnyShapeStyle(Color(nsColor: .textBackgroundColor))
                      : AnyShapeStyle(Color.primary.opacity(isHoveringName ? 0.07 : 0)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isEditingName ? Color.accentColor : .clear, lineWidth: 2)
        }
        // Keep the text aligned with the caption below while the padding
        // leaves room for the highlight.
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onTapGesture { isEditingName = true }
        .onHover { isHoveringName = $0 }
        .animation(.easeOut(duration: 0.12), value: isEditingName)
        .animation(.easeOut(duration: 0.12), value: isHoveringName)
        .help(isEditingName ? "" : "Click to rename")
    }

    @ViewBuilder
    private func nameStatus(for recipe: FilmRecipe) -> some View {
        Group {
            if let renameError {
                Text(renameError)
                    .foregroundStyle(.red)
            } else if isEditingName {
                Text("Return to save · Esc to cancel")
                    .foregroundStyle(.secondary)
            } else if nameSavedAt != nil {
                Label("Name saved", systemImage: "checkmark")
                    .foregroundStyle(.green)
            } else {
                Text(isInUse(recipe) ? "In use" : "Saved recipe")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .transition(.opacity)
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
                isSavingRecipe = true
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

    /// The recipe as its canister should read while the name is being edited.
    private func previewRecipe(_ recipe: FilmRecipe) -> FilmRecipe {
        var preview = recipe
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            preview.name = name
        }
        return preview
    }

    private func isInUse(_ recipe: FilmRecipe) -> Bool {
        recipe.id == model.selectedRecipeID && !model.isRecipeModified
    }

    private func loadDraftName() {
        draftName = selectedRecipe?.name ?? ""
        renameError = nil
        nameSavedAt = nil
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
            confirmNameSaved()
        } else {
            renameError = "Use a name that isn’t empty or already taken."
        }
    }

    /// Shows "Name saved" for a moment after a rename lands.
    private func confirmNameSaved() {
        let savedAt = Date()
        withAnimation { nameSavedAt = savedAt }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if nameSavedAt == savedAt {
                withAnimation { nameSavedAt = nil }
            }
        }
    }

    private func deleteSelectedRecipe() {
        guard let selectedID else { return }
        model.deleteRecipe(id: selectedID)
        self.selectedID = model.savedRecipes.first?.id
    }
}

/// A saved recipe's canister, with its name printed on it, as a small glyph.
struct MiniCanister: View {
    let style: CanisterStyle
    let name: String
    let height: CGFloat

    init(recipe: FilmRecipe, design: CanisterDesign? = nil, height: CGFloat) {
        style = design.map { CanisterStyle(design: $0, recipe: recipe) }
            ?? CanisterStyle(recipe: recipe, isModified: false)
        name = recipe.name
        self.height = height
    }

    var body: some View {
        FilmCanisterView(style: style, recipeName: name, height: height)
            .frame(width: CanisterGeometry.width * height / CanisterGeometry.height + 2, height: height)
            .accessibilityHidden(true)
    }
}

/// The canister library in a popover, for a recipe that's already saved.
private struct CanisterPicker: View {
    let recipe: FilmRecipe
    let onChoose: (CanisterDesign) -> Void

    private var current: CanisterDesign { CanisterDesign.resolved(for: recipe) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Canister")
                    .font(.headline)
                Spacer()
                Button("Shuffle", systemImage: "shuffle") {
                    if let design = CanisterDesign.automatic.filter({ $0 != current }).randomElement() {
                        onChoose(design)
                    }
                }
                .controlSize(.small)
            }
            CanisterGrid(recipe: recipe, selection: current, onChoose: onChoose)
        }
        .padding(14)
    }
}
