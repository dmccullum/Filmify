import AppKit
import GranularCore
import SwiftUI
import UniformTypeIdentifiers

/// The Recipe Library: every recipe down the side, the chosen one large on
/// the right. Built-in recipes can be used, duplicated and exported; saved
/// ones can also be renamed, repackaged, reordered and deleted.
struct RecipeLibraryView: View {
    static let windowID = "recipe-library"

    @Environment(AppModel.self) private var model
    @State private var pendingAction: RecipeLibraryAction?
    @State private var isSavingRecipe = false
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            RecipeLibrarySidebar(pendingAction: $pendingAction, isSavingRecipe: $isSavingRecipe)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if let recipe = selectedRecipe {
                RecipeLibraryDetail(recipe: recipe, pendingAction: $pendingAction)
                    .id(recipe.id)
            } else {
                ContentUnavailableView(
                    "No Recipe Selected",
                    systemImage: "film.stack",
                    description: Text("Choose a recipe to see its settings or put it to use.")
                )
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle("Recipe Library")
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let recipeFiles = urls.filter(RecipeFile.isRecipeFile)
            guard !recipeFiles.isEmpty else { return false }
            model.importRecipes(from: recipeFiles, in: .library)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .confirmingRecipeDeletion(in: .library)
        .sheet(isPresented: $isSavingRecipe) {
            SaveRecipeSheet { model.recipeLibrarySelection = $0.id }
                .environment(model)
        }
        .alert(
            model.recipeLibraryAlert?.title ?? "",
            isPresented: Binding(
                get: { model.recipeLibraryAlert != nil },
                set: { if !$0 { model.recipeLibraryAlert = nil } }
            ),
            presenting: model.recipeLibraryAlert,
            actions: { _ in Button("OK", role: .cancel) {} },
            message: { alert in Text(alert.message) }
        )
        .background(WindowReader { model.attachRecipeLibraryWindow($0) })
        .onAppear {
            keepSelectionValid()
            importWaitingRecipeFiles()
        }
        .onChange(of: model.availableRecipes.map(\.id)) { _, _ in
            keepSelectionValid()
        }
        .onReceive(NotificationCenter.default.publisher(for: .granularOpenRecipeFiles)) { _ in
            importWaitingRecipeFiles()
        }
    }

    private var selectedRecipe: FilmRecipe? {
        guard let id = model.recipeLibrarySelection else { return nil }
        return model.availableRecipes.first { $0.id == id }
    }

    /// Shows the recipe in use when nothing, or something now gone, is selected.
    private func keepSelectionValid() {
        if selectedRecipe == nil {
            model.recipeLibrarySelection = model.selectedRecipeID
        }
    }

    private func importWaitingRecipeFiles() {
        let urls = RecipeFileInbox.take()
        guard !urls.isEmpty else { return }
        model.importRecipes(from: urls, in: .library)
        model.recipeLibraryWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Something asked of the detail from elsewhere, such as Rename in a row's
/// context menu, carried out once that recipe is showing.
private enum RecipeLibraryAction: Equatable {
    case rename(String)
    case chooseCanister(String)

    var recipeID: String {
        switch self {
        case .rename(let id), .chooseCanister(let id): id
        }
    }
}

// MARK: - Sidebar

private struct RecipeLibrarySidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var pendingAction: RecipeLibraryAction?
    @Binding var isSavingRecipe: Bool

    var body: some View {
        @Bindable var model = model

        List(selection: $model.recipeLibrarySelection) {
            Section("Built-in") {
                ForEach(FilmRecipe.builtIns) { recipe in
                    RecipeLibraryRow(recipe: recipe)
                }
            }
            Section("My Recipes") {
                ForEach(model.savedRecipes) { recipe in
                    RecipeLibraryRow(recipe: recipe)
                }
                .onMove { source, destination in
                    model.moveSavedRecipes(fromOffsets: source, toOffset: destination)
                }
                if model.savedRecipes.isEmpty {
                    Text("Recipes you save or import appear here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let recipe = model.availableRecipes.first(where: { $0.id == id }) {
                contextMenu(for: recipe)
            }
        } primaryAction: { ids in
            if let id = ids.first, let recipe = model.availableRecipes.first(where: { $0.id == id }) {
                model.selectRecipe(recipe)
            }
        }
        .onDeleteCommand {
            if let id = model.recipeLibrarySelection {
                model.requestDeletingRecipe(id: id, in: .library)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
    }

    @ViewBuilder
    private func contextMenu(for recipe: FilmRecipe) -> some View {
        let isSaved = model.isSavedRecipe(recipe.id)

        Button("Use Recipe") {
            model.selectRecipe(recipe)
        }
        .disabled(model.isInUse(recipe))

        Divider()

        if isSaved {
            Button("Rename") {
                show(.rename(recipe.id))
            }
        }
        Button("Duplicate") {
            if let copy = model.duplicateRecipe(id: recipe.id) {
                model.recipeLibrarySelection = copy.id
            }
        }
        if isSaved {
            Button("Change Canister…") {
                show(.chooseCanister(recipe.id))
            }
        }
        Button("Export…") {
            model.exportRecipe(recipe)
        }

        if isSaved {
            Divider()
            Button("Delete…", role: .destructive) {
                model.requestDeletingRecipe(id: recipe.id, in: .library)
            }
        }
    }

    private func show(_ action: RecipeLibraryAction) {
        model.recipeLibrarySelection = action.recipeID
        pendingAction = action
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 2) {
                Menu {
                    Button("Save Current Settings as Recipe…") {
                        isSavingRecipe = true
                    }
                    Button("Import Recipe…") {
                        model.chooseRecipesToImport()
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Save the current settings as a recipe, or import one")
                .accessibilityLabel("Add Recipe")

                Button {
                    if let id = model.recipeLibrarySelection {
                        model.requestDeletingRecipe(id: id, in: .library)
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(!model.isSavedRecipe(model.recipeLibrarySelection ?? ""))
                .help("Delete the selected recipe")
                .accessibilityLabel("Delete Recipe")

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
        }
    }
}

private struct RecipeLibraryRow: View {
    @Environment(AppModel.self) private var model
    let recipe: FilmRecipe

    var body: some View {
        let isInUse = model.isInUse(recipe)

        HStack(spacing: 10) {
            MiniCanister(recipe: recipe, height: 30)
            Text(recipe.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if isInUse {
                RecipeInUseMark()
            }
        }
        .padding(.vertical, 1)
        .tag(recipe.id)
        .itemProvider { model.recipeItemProvider(for: recipe) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isInUse ? "\(recipe.name), in use" : recipe.name)
    }
}

/// A checkmark beside the recipe in use, as a menu would mark it. It turns
/// white on a selected row, where the accent color would disappear.
private struct RecipeInUseMark: View {
    @Environment(\.backgroundProminence) private var backgroundProminence

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.body)
            .foregroundStyle(backgroundProminence == .increased ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
            .help("In use")
            .accessibilityHidden(true)
    }
}

// MARK: - Detail

private struct RecipeLibraryDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recipe: FilmRecipe
    @Binding var pendingAction: RecipeLibraryAction?

    @State private var draftName = ""
    @State private var renameError: String?
    @State private var isChoosingCanister = false
    @State private var isHoveringCanister = false
    @State private var isHoveringName = false
    @State private var nameSavedAt: Date?
    @FocusState private var isEditingName: Bool

    private var isSaved: Bool { model.isSavedRecipe(recipe.id) }
    private var isInUse: Bool { model.isInUse(recipe) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 28) {
                    VStack(spacing: 8) {
                        canister
                        Text("Drag to the Finder to share")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if isSaved {
                            nameField
                        } else {
                            Text(recipe.name)
                                .font(.title2.weight(.semibold))
                                .textSelection(.enabled)
                        }
                        status
                        actions
                            .padding(.top, 6)
                    }
                    .padding(.top, 10)
                }

                Divider()

                settings
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            draftName = recipe.name
            carryOut(pendingAction)
        }
        .onChange(of: pendingAction) { _, action in
            carryOut(action)
        }
        .onChange(of: recipe.name) { _, name in
            if !isEditingName { draftName = name }
        }
        .onChange(of: isEditingName) { _, isEditing in
            if !isEditing {
                commitRename()
            }
        }
    }

    // MARK: Canister

    private var canister: some View {
        Button {
            if isSaved { isChoosingCanister = true }
        } label: {
            MiniCanister(recipe: previewRecipe, height: 170)
                .padding(14)
                .background(
                    .quaternary.opacity(isSaved && isHoveringCanister ? 0.8 : 0.35),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(alignment: .bottomTrailing) {
                    if isSaved {
                        Image(systemName: "paintbrush.pointed.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor, in: Circle())
                            .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                            .offset(x: 6, y: 6)
                    }
                }
                .scaleEffect(isSaved && isHoveringCanister && !reduceMotion ? 1.02 : 1)
                .animation(.easeOut(duration: 0.12), value: isHoveringCanister)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringCanister = $0 }
        .onDrag {
            model.recipeItemProvider(for: recipe)
        } preview: {
            MiniCanister(recipe: recipe, height: 96)
        }
        .help(isSaved ? "Choose a canister for this recipe, or drag it to the Finder to share it" : "Drag to the Finder to share this recipe")
        .accessibilityLabel("Canister: \(CanisterDesign.resolved(for: recipe).name)")
        .accessibilityHint(isSaved ? "Chooses a different canister" : "")
        .popover(isPresented: $isChoosingCanister, arrowEdge: .trailing) {
            CanisterPicker(recipe: previewRecipe) { design in
                model.setCanister(design.id, forRecipe: recipe.id)
            }
        }
    }

    // MARK: Name and status

    /// The recipe name, which reads as a title at rest but shows a pencil and
    /// a hover highlight, and becomes a proper field while it's being edited.
    private var nameField: some View {
        HStack(spacing: 6) {
            TextField("Recipe Name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .focused($isEditingName)
                .onSubmit { isEditingName = false }
                .onExitCommand {
                    draftName = recipe.name
                    renameError = nil
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
        // Keep the text aligned with the lines below while the padding
        // leaves room for the highlight.
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onTapGesture { isEditingName = true }
        .onHover { isHoveringName = $0 }
        .animation(.easeOut(duration: 0.12), value: isEditingName)
        .animation(.easeOut(duration: 0.12), value: isHoveringName)
        .help(isEditingName ? "" : "Click to rename")
    }

    private var status: some View {
        HStack(spacing: 8) {
            if isInUse {
                RecipeInUseBadge()
            }
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
                    Text(isSaved ? "Saved recipe" : "Built-in recipe")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .transition(.opacity)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Use Recipe") {
                model.selectRecipe(recipe)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInUse)
            .help(isInUse ? "This recipe is in use" : "Put this recipe to use")

            Button("Duplicate") {
                if let copy = model.duplicateRecipe(id: recipe.id) {
                    model.recipeLibrarySelection = copy.id
                }
            }
            .help("Save a copy of this recipe that you can change")

            Button("Export…") {
                model.exportRecipe(recipe)
            }
            .help("Save this recipe as a file to keep or share")
        }
    }

    // MARK: Settings

    private var settings: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
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

    // MARK: Actions

    /// The recipe as its canister should read while the name is being edited.
    private var previewRecipe: FilmRecipe {
        var preview = recipe
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSaved, !name.isEmpty {
            preview.name = name
        }
        return preview
    }

    private func carryOut(_ action: RecipeLibraryAction?) {
        guard let action, action.recipeID == recipe.id, isSaved else { return }
        pendingAction = nil
        // Wait a moment for the detail to be on screen before focusing or
        // anchoring a popover to it.
        Task { @MainActor in
            switch action {
            case .rename: isEditingName = true
            case .chooseCanister: isChoosingCanister = true
            }
        }
    }

    private func commitRename() {
        guard isSaved else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != recipe.name else {
            draftName = recipe.name
            renameError = nil
            return
        }
        if model.renameRecipe(id: recipe.id, to: name) {
            draftName = name
            renameError = nil
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
}

/// “In Use”, in the accent color, for the recipe that's the current look.
private struct RecipeInUseBadge: View {
    var body: some View {
        Label("In Use", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.tint.opacity(0.14), in: Capsule())
            .help("This recipe is the look in use")
    }
}

// MARK: - Shared pieces

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

/// Hands over the window a view is in, once it's in one.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> ReportingView {
        ReportingView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: ReportingView, context: Context) {}

    final class ReportingView: NSView {
        let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}

// MARK: - Presenting

extension View {
    /// Asks before deleting a recipe, as a sheet on this window, when the
    /// request came from it.
    func confirmingRecipeDeletion(in window: RecipeWindow) -> some View {
        modifier(RecipeDeletionConfirmation(window: window))
    }

    /// Opens the Recipe Library when asked from a control that can't open
    /// windows itself, and imports recipe files opened from the Finder.
    func openingRecipeLibrary() -> some View {
        modifier(RecipeLibraryOpener())
    }
}

private struct RecipeDeletionConfirmation: ViewModifier {
    @Environment(AppModel.self) private var model
    let window: RecipeWindow

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete “\(model.recipeDeletionRequest?.recipe.name ?? "")”?",
            isPresented: Binding(
                get: { model.recipeDeletionRequest?.window == window },
                set: { if !$0 { model.recipeDeletionRequest = nil } }
            ),
            titleVisibility: .visible,
            presenting: model.recipeDeletionRequest
        ) { request in
            Button("Delete", role: .destructive) {
                model.deleteRecipe(id: request.recipe.id, in: window)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You can undo this with Edit ▸ Undo.")
        }
    }
}

private struct RecipeLibraryOpener: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onChange(of: model.showRecipeManager, initial: true) { _, isRequested in
                guard isRequested else { return }
                model.showRecipeManager = false
                openWindow(id: RecipeLibraryView.windowID)
            }
            .onAppear(perform: importWaitingRecipeFiles)
            .onReceive(NotificationCenter.default.publisher(for: .granularOpenRecipeFiles)) { _ in
                importWaitingRecipeFiles()
            }
    }

    /// Imports into the library and shows it, where any trouble is reported.
    private func importWaitingRecipeFiles() {
        let urls = RecipeFileInbox.take()
        guard !urls.isEmpty else { return }
        model.importRecipes(from: urls, in: .library)
        openWindow(id: RecipeLibraryView.windowID)
    }
}
