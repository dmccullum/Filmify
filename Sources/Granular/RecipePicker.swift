import GranularCore
import SwiftUI

/// The recipe control in Edit mode's Adjustments header: the recipe's own
/// canister beside its name, opening a grid of every recipe's canister.
struct RecipeMenu: View {
    @Environment(AppModel.self) private var model
    @State private var isPresented = false
    @State private var buttonFrame = CGRect.zero

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                FilmCanisterView(
                    style: CanisterStyle(recipe: model.currentRecipe, isModified: model.isRecipeModified),
                    recipeName: model.recipeDisplayName,
                    height: 40
                )
                .frame(width: CanisterGeometry.width * 40 / CanisterGeometry.height, height: 40)
                Text(model.recipeDisplayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .help("Choose or save a film recipe")
        .accessibilityLabel("Recipe: \(model.recipeDisplayName)")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { buttonFrame = $0 }
        .popover(isPresented: $isPresented, attachmentAnchor: popoverAnchor, arrowEdge: .bottom) {
            RecipeGrid(dismiss: { isPresented = false })
                .environment(model)
        }
    }

    /// The button sits at the window’s trailing edge and the grid is wider than
    /// the room beside it, so a popover centred on the button would hang off the
    /// window. Aim it at a point far enough inboard that the popover ends just
    /// inside the edge, still below the header where the arrow points.
    private var popoverAnchor: PopoverAttachmentAnchor {
        let windowWidth = NSApp.keyWindow?.contentView?.bounds.width ?? 0
        let roomAfterButton = windowWidth > buttonFrame.maxX ? windowWidth - buttonFrame.maxX : 16
        let overhang = RecipeGrid.popoverWidth / 2 + 8 - roomAfterButton - buttonFrame.width / 2
        let shift = max(0, overhang)
        return .rect(.rect(CGRect(
            x: (buttonFrame.width - 1) / 2 - shift,
            y: 0,
            width: 1,
            height: buttonFrame.height
        )))
    }
}

/// Every recipe as its canister, in the manner of the Film Stock grid, with
/// the recipe actions underneath.
private struct RecipeGrid: View {
    @Environment(AppModel.self) private var model
    let dismiss: () -> Void
    @FocusState private var isFocused: Bool

    private static let columnCount = 4
    static var popoverWidth: CGFloat { CGFloat(columnCount) * (RecipeTile.width + 8) + 20 }
    private let columns = Array(
        repeating: GridItem(.fixed(RecipeTile.width), spacing: 8, alignment: .top),
        count: columnCount
    )

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.isRecipeModified {
                        Label("Your edits aren’t saved to a recipe yet.", systemImage: "pencil.and.scribble")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    section("Built-in", recipes: FilmRecipe.builtIns)
                    if !model.savedRecipes.isEmpty {
                        section("My Recipes", recipes: model.savedRecipes)
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 460)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            actions
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: Self.popoverWidth)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.leftArrow) { move(by: -1) }
        .onKeyPress(.rightArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -Self.columnCount) }
        .onKeyPress(.downArrow) { move(by: Self.columnCount) }
        .onKeyPress(.return) {
            dismiss()
            return .handled
        }
    }

    private func section(_ title: String, recipes: [FilmRecipe]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(recipes) { recipe in
                    RecipeTile(recipe: recipe, isSelected: isSelected(recipe)) {
                        model.selectRecipe(recipe)
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button("Save New…", systemImage: "plus") {
                dismiss()
                model.beginSavingRecipe()
            }
            if model.isSelectedRecipeCustom {
                Button {
                    model.updateSelectedRecipe()
                } label: {
                    Label {
                        Text("Update “\(model.currentRecipe.name)”")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .disabled(!model.isRecipeModified)
                .help("Save your edits to “\(model.currentRecipe.name)”")
            }
            Spacer()
            Button("Manage…") {
                dismiss()
                model.showRecipeManager = true
            }
        }
        .controlSize(.small)
    }

    private func isSelected(_ recipe: FilmRecipe) -> Bool {
        !model.isRecipeModified && recipe.id == model.selectedRecipeID
    }

    private func move(by offset: Int) -> KeyPress.Result {
        let order = model.availableRecipes
        guard let index = order.firstIndex(where: { $0.id == model.selectedRecipeID }) else { return .ignored }
        model.selectRecipe(order[max(0, min(order.count - 1, index + offset))])
        return .handled
    }
}

private struct RecipeTile: View {
    static let width: CGFloat = 84

    let recipe: FilmRecipe
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                MiniCanister(recipe: recipe, height: 88)
                    .frame(width: Self.width, height: 104)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    }

                Text(recipe.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(recipe.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Canisters

/// The canister library, each tin carrying the recipe's own name.
struct CanisterGrid: View {
    let recipe: FilmRecipe
    let selection: CanisterDesign
    let onChoose: (CanisterDesign) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 8), count: 7), spacing: 10) {
            ForEach(CanisterDesign.library) { design in
                Button {
                    onChoose(design)
                } label: {
                    VStack(spacing: 4) {
                        MiniCanister(recipe: recipe, design: design, height: 78)
                            .padding(4)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(design == selection ? Color.accentColor : .clear, lineWidth: 2)
                            }
                        Text(design.name)
                            .font(.caption2)
                            .foregroundStyle(design == selection ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(design.name)
                .accessibilityAddTraits(design == selection ? .isSelected : [])
            }
        }
    }
}

/// Names the current settings and packages them in a canister.
struct SaveRecipeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onSaved: (FilmRecipe) -> Void = { _ in }

    @State private var name = ""
    @State private var design = CanisterDesign.automatic.randomElement() ?? .tape
    @FocusState private var isEditingName: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The recipe as it will be printed, following the name as it's typed.
    private var preview: FilmRecipe {
        var recipe = model.recipe
        recipe.name = trimmedName.isEmpty ? "Untitled" : trimmedName
        return recipe
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                MiniCanister(recipe: preview, design: design, height: 110)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Save Film Recipe")
                        .font(.headline)
                    TextField("Recipe Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingName)
                        .onSubmit(save)
                    Text("Saves every adjustment and the global strength.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Canister")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Shuffle", systemImage: "shuffle") {
                        design = CanisterDesign.automatic.filter { $0 != design }.randomElement() ?? design
                    }
                    .controlSize(.small)
                }
                CanisterGrid(recipe: preview, selection: design) { design = $0 }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            name = model.suggestedRecipeName
            isEditingName = true
        }
    }

    private func save() {
        guard let recipe = model.saveCurrentAsRecipe(named: trimmedName, canister: design.id) else { return }
        dismiss()
        onSaved(recipe)
    }
}
