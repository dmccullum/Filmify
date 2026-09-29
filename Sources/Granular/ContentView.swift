import AppKit
import GranularCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model

        let showsCameraBody = model.operationMode == .drop

        // A mode switch is one motion: the window resizes while the two modes
        // crossfade, each held at its own size so neither reflows mid-move.
        ZStack {
            if showsCameraBody || model.isSettlingWindow {
                AlloySurface()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            switch model.operationMode {
            case .drop:
                DropModeView()
                    .holdingLayoutDuringModeChange(for: .drop)
                    .transition(.opacity)
            case .edit:
                EditModeView()
                    .holdingLayoutDuringModeChange(for: .edit)
                    .transition(.opacity)
            }
        }
        .animation(modeContentAnimation, value: model.operationMode)
        .frame(minWidth: 620, minHeight: 340)
        .overlay(alignment: .topTrailing) {
            if !showsCameraBody, !model.isSettlingWindow {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                    .offset(x: -310)
                    .ignoresSafeArea(.container, edges: .top)
                    .allowsHitTesting(false)
            }
        }
        .toolbarBackgroundVisibility(showsCameraBody || model.isSettlingWindow ? .hidden : .automatic, for: .windowToolbar)
        .toolbar(removing: showsCameraBody ? .title : nil)
        .toolbar {
            if showsCameraBody {
                ToolbarItem(placement: .principal) {
                    CameraNameplate()
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItem(placement: .primaryAction) {
                ModePicker()
            }
        }
        .onChange(of: model.operationMode) { _, _ in
            model.modeDidChange()
        }
        .onAppear {
            model.scheduleWindowResize(for: model.operationMode, animated: false)
        }
        .sheet(isPresented: $model.showRecipeManager) {
            RecipeManagerView()
                .environment(model)
        }
        .onReceive(NotificationCenter.default.publisher(for: .granularOpenURLs)) { notification in
            guard let urls = notification.object as? [URL] else { return }
            if model.operationMode == .edit {
                model.openForEditing(urls)
            } else {
                Task { await model.processInstantly(urls) }
            }
        }
        .alert(
            "Granular Couldn’t Start",
            isPresented: Binding(
                get: { model.startupError != nil },
                set: { if !$0 { model.startupError = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(model.startupError ?? "Unknown error")
            }
        )
    }

    private var modeContentAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : AppModel.modeTransitionAnimation
    }
}

private struct ModeChangeLayoutHold: ViewModifier {
    @Environment(AppModel.self) private var model
    let mode: OperationMode
    @State private var settledSize: CGSize?

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let size = layoutSize(live: proxy.size)
            content
                .frame(width: size.width, height: size.height)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .onChange(of: proxy.size, initial: true) { _, newSize in
                    if !model.isSettlingWindow {
                        settledSize = newSize
                    }
                }
        }
    }

    /// Live size normally; during a mode switch, the arriving mode is laid out
    /// at its final size and the leaving mode keeps the size it had. Both are
    /// pinned top-centre, where the window resizes around them.
    private func layoutSize(live: CGSize) -> CGSize {
        guard model.isSettlingWindow else { return live }
        if model.operationMode == mode {
            return model.arrivingLayoutSize ?? live
        }
        return settledSize ?? live
    }
}

extension View {
    func holdingLayoutDuringModeChange(for mode: OperationMode) -> some View {
        modifier(ModeChangeLayoutHold(mode: mode))
    }
}

private struct ModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Picker("Mode", selection: $model.operationMode) {
            ForEach(OperationMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

struct RecipeMenu: View {
    @Environment(AppModel.self) private var model
    let showsRecipeName: Bool

    init(showsRecipeName: Bool = false) {
        self.showsRecipeName = showsRecipeName
    }

    var body: some View {
        Group {
            if showsRecipeName {
                nativeButton
            } else {
                nativeButton
                    .background(
                        .quaternary.opacity(0.34),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
        }
        .fixedSize()
        .help("Choose or save a film recipe")
    }

    private var nativeButton: some View {
        NativeRecipeMenuButton(
            model: model,
            showsRecipeName: showsRecipeName,
            recipeName: model.recipeDisplayName,
            selectedRecipeID: model.selectedRecipeID,
            savedRecipes: model.savedRecipes,
            operationMode: model.operationMode,
            isSelectedRecipeCustom: model.isSelectedRecipeCustom,
            isRecipeModified: model.isRecipeModified
        )
    }
}

/// Shows the recipe menu from a custom control, such as Instant mode's film canister.
@MainActor
enum RecipeMenuPresenter {
    static func popUp(model: AppModel) {
        let coordinator = NativeRecipeMenuButton.Coordinator(model: model)
        coordinator.update(
            model: model,
            selectedRecipeID: model.selectedRecipeID,
            savedRecipes: model.savedRecipes,
            operationMode: model.operationMode,
            isSelectedRecipeCustom: model.isSelectedRecipeCustom,
            isRecipeModified: model.isRecipeModified
        )
        coordinator.showMenuAtMouseLocation()
    }
}

@MainActor
private struct NativeRecipeMenuButton: NSViewRepresentable {
    let model: AppModel
    let showsRecipeName: Bool
    let recipeName: String
    let selectedRecipeID: String
    let savedRecipes: [FilmRecipe]
    let operationMode: OperationMode
    let isSelectedRecipeCustom: Bool
    let isRecipeModified: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
        button.setButtonType(.momentaryPushIn)
        button.focusRingType = .default
        button.imageHugsTitle = true
        button.imageScaling = .scaleNone
        button.setAccessibilityLabel("Recipe: \(recipeName)")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.update(
            model: model,
            selectedRecipeID: selectedRecipeID,
            savedRecipes: savedRecipes,
            operationMode: operationMode,
            isSelectedRecipeCustom: isSelectedRecipeCustom,
            isRecipeModified: isRecipeModified
        )

        button.setAccessibilityLabel("Recipe: \(recipeName)")
        button.toolTip = "Choose or save a film recipe"

        if showsRecipeName {
            button.title = recipeName
            button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.image = symbol("chevron.down", pointSize: 8, weight: .semibold)
            button.imagePosition = .imageTrailing
            button.isBordered = false
            button.bezelStyle = .inline
            button.controlSize = .small
            button.contentTintColor = .secondaryLabelColor
        } else {
            button.title = "⌄"
            button.font = .systemFont(ofSize: 11, weight: .semibold)
            button.image = symbol("camera.filters", pointSize: 13, weight: .medium)
            button.imagePosition = .imageLeading
            button.isBordered = false
            button.bezelStyle = .inline
            button.controlSize = .regular
            button.contentTintColor = nil
        }

        button.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        let fittingSize = nsView.fittingSize
        return CGSize(
            width: showsRecipeName ? fittingSize.width : 58,
            height: showsRecipeName ? 20 : 32
        )
    }

    private func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    }

    @MainActor
    final class Coordinator: NSObject {
        private var model: AppModel
        private var selectedRecipeID = ""
        private var savedRecipes: [FilmRecipe] = []
        private var operationMode: OperationMode = .drop
        private var isSelectedRecipeCustom = false
        private var isRecipeModified = false

        init(model: AppModel) {
            self.model = model
        }

        func update(
            model: AppModel,
            selectedRecipeID: String,
            savedRecipes: [FilmRecipe],
            operationMode: OperationMode,
            isSelectedRecipeCustom: Bool,
            isRecipeModified: Bool
        ) {
            self.model = model
            self.selectedRecipeID = selectedRecipeID
            self.savedRecipes = savedRecipes
            self.operationMode = operationMode
            self.isSelectedRecipeCustom = isSelectedRecipeCustom
            self.isRecipeModified = isRecipeModified
        }

        func showMenuAtMouseLocation() {
            makeMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = makeMenu()
            let origin = NSPoint(x: 0, y: sender.bounds.minY - 3)
            menu.popUp(positioning: nil, at: origin, in: sender)
        }

        @objc private func selectRecipe(_ item: NSMenuItem) {
            guard let recipeID = item.representedObject as? String,
                  let recipe = model.availableRecipes.first(where: { $0.id == recipeID }) else { return }
            model.selectRecipe(recipe)
        }

        @objc private func saveRecipe() {
            model.saveCurrentAsRecipe()
        }

        @objc private func updateRecipe() {
            model.updateSelectedRecipe()
        }

        @objc private func deleteRecipe() {
            model.deleteSelectedRecipe()
        }

        @objc private func manageRecipes() {
            model.showRecipeManager = true
        }

        private func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false

            if isRecipeModified {
                let custom = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
                custom.state = .on
                custom.isEnabled = false
                menu.addItem(custom)
                menu.addItem(.separator())
            }

            addRecipeSection("Built-in", recipes: FilmRecipe.builtIns, to: menu)

            if !savedRecipes.isEmpty {
                menu.addItem(.separator())
                addRecipeSection("My Recipes", recipes: savedRecipes, to: menu)
            }

            if operationMode == .edit {
                menu.addItem(.separator())
                addAction(
                    "Save New Recipe…",
                    symbol: "plus",
                    action: #selector(saveRecipe),
                    to: menu
                )
                if isSelectedRecipeCustom {
                    addAction(
                        "Update “\(model.currentRecipe.name)”",
                        symbol: "square.and.arrow.down",
                        action: #selector(updateRecipe),
                        to: menu
                    )
                    addAction(
                        "Delete “\(model.currentRecipe.name)”…",
                        symbol: "trash",
                        action: #selector(deleteRecipe),
                        to: menu
                    )
                }
            }

            menu.addItem(.separator())
            addAction("Manage Recipes…", symbol: "list.bullet", action: #selector(manageRecipes), to: menu)
            return menu
        }

        private func addRecipeSection(_ title: String, recipes: [FilmRecipe], to menu: NSMenu) {
            menu.addItem(.sectionHeader(title: title))
            for recipe in recipes {
                let item = NSMenuItem(title: recipe.name, action: #selector(selectRecipe(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = recipe.id
                item.state = !isRecipeModified && recipe.id == selectedRecipeID ? .on : .off
                menu.addItem(item)
            }
        }

        private func addAction(_ title: String, symbol: String, action: Selector, to menu: NSMenu) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
    }
}
