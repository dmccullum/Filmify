import GranularCore
import SwiftUI

/// Every recipe on the phone: the ones made here or imported, which can be
/// renamed, reordered, shared and deleted, and the built-in ones, which can
/// be copied and shared.
struct RecipeLibrarySheet: View {
    @Environment(Darkroom.self) private var darkroom
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var renaming: FilmRecipe?
    @State private var newName = ""
    @State private var deleting: FilmRecipe?
    @State private var highlighted: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if !darkroom.savedRecipes.isEmpty {
                        Section("My Recipes") {
                            ForEach(darkroom.savedRecipes) { recipe in
                                row(recipe)
                            }
                            .onDelete { offsets in
                                let doomed = offsets.map { darkroom.savedRecipes[$0].id }
                                withAnimation(.smooth) { doomed.forEach(darkroom.deleteRecipe) }
                            }
                            .onMove { source, destination in
                                withAnimation(.smooth) { darkroom.moveSavedRecipes(fromOffsets: source, toOffset: destination) }
                            }
                        }
                    }
                    Section("Built In") {
                        ForEach(FilmRecipe.builtIns) { recipe in
                            row(recipe)
                        }
                    }
                }
                .onChange(of: darkroom.lastImportedID, initial: true) { _, id in
                    guard let id else { return }
                    darkroom.lastImportedID = nil
                    withAnimation(.smooth) {
                        proxy.scrollTo(id, anchor: .center)
                        highlighted = id
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        withAnimation(.smooth) { if highlighted == id { highlighted = nil } }
                    }
                }
            }
            .navigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Import", systemImage: "square.and.arrow.down") { isImporting = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                        .disabled(darkroom.savedRecipes.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.granularRecipe],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    withAnimation(.smooth) { _ = darkroom.importRecipes(from: urls) }
                }
            }
            .alert(
                darkroom.importAlert?.title ?? "",
                isPresented: Binding { darkroom.importAlert != nil } set: { if !$0 { darkroom.importAlert = nil } }
            ) {
                Button("OK") {}
            } message: {
                Text(darkroom.importAlert?.message ?? "")
            }
            .alert("Rename Recipe", isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } }) {
                TextField("Name", text: $newName)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    if let renaming { withAnimation(.smooth) { _ = darkroom.renameRecipe(id: renaming.id, to: newName) } }
                }
                .disabled(!canRename)
            }
            .confirmationDialog(
                "Delete “\(deleting?.name ?? "")”?",
                isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } },
                titleVisibility: .visible,
                presenting: deleting
            ) { recipe in
                Button("Delete", role: .destructive) {
                    withAnimation(.smooth) { darkroom.deleteRecipe(id: recipe.id) }
                }
            }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.selection, trigger: darkroom.selectedRecipeID)
        .sensoryFeedback(.success, trigger: darkroom.lastImportedID) { _, id in id != nil }
        .sensoryFeedback(.warning, trigger: darkroom.importAlert?.id)
    }

    /// A name that isn't empty and isn't another recipe's.
    private var canRename: Bool {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !darkroom.availableRecipes.contains {
            $0.id != renaming?.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func row(_ recipe: FilmRecipe) -> some View {
        let isSaved = darkroom.isSavedRecipe(recipe.id)
        let isInUse = !darkroom.isRecipeModified && recipe.id == darkroom.selectedRecipeID
        return Button {
            withAnimation(.smooth) { darkroom.selectRecipe(recipe) }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                FilmCanisterView(
                    style: CanisterStyle(recipe: recipe, isModified: false),
                    recipeName: recipe.name,
                    height: 36,
                    castsShadow: false
                )
                .frame(width: CanisterGeometry.width * 36 / CanisterGeometry.height, height: 36)
                Text(recipe.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if isInUse {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(recipe.id)
        .listRowBackground(highlighted == recipe.id ? Color.accentColor.opacity(0.2) : nil)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
        .contextMenu {
            if isSaved {
                Button("Rename", systemImage: "pencil") {
                    newName = recipe.name
                    renaming = recipe
                }
            }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                withAnimation(.smooth) { _ = darkroom.duplicateRecipe(id: recipe.id) }
            }
            if isSaved {
                Picker("Canister", systemImage: "cylinder", selection: canister(for: recipe)) {
                    ForEach(CanisterDesign.library) { design in
                        Text(design.name).tag(design.id)
                    }
                }
                .pickerStyle(.menu)
            }
            ShareLink(item: RecipeDocument(recipe: recipe), preview: SharePreview(recipe.name)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            if isSaved {
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = recipe }
            }
        }
    }

    private func canister(for recipe: FilmRecipe) -> Binding<String> {
        Binding {
            CanisterDesign.resolved(for: recipe).id
        } set: { id in
            withAnimation(.smooth) { darkroom.setCanister(id, forRecipe: recipe.id) }
        }
    }
}
