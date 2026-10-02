import GranularCore
import PhotosUI
import SwiftUI

struct EditView: View {
    @Environment(Darkroom.self) private var darkroom
    @Environment(Editor.self) private var editor

    @State private var effect = EditEffect.tone
    @State private var picked: PhotosPickerItem?
    @State private var canvas = CanvasGeometry()
    /// How much of the bottom the controls cover; the photo fits above them.
    @State private var controlsHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            photo
                .ignoresSafeArea(edges: .bottom)

            controls
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
        }
        .coordinateSpace(.named(PhotoCanvas.space))
        .tint(.white)
        .onAppear { editor.refreshStockThumbnails() }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { await editor.open(item) }
        }
        .onChange(of: darkroom.recipe) { old, new in
            editor.schedulePreview()
            if old.tone != new.tone {
                editor.refreshStockThumbnails()
            }
        }
        .sensoryFeedback(.selection, trigger: effect)
        .alert(
            editor.failure?.title ?? "",
            isPresented: Binding { editor.failure != nil } set: { if !$0 { editor.failure = nil } },
            presenting: editor.failure
        ) { failure in
            if failure == .photosAccess {
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { failure in
            Text(failure.message)
        }
    }

    // MARK: Photo

    @ViewBuilder
    private var photo: some View {
        @Bindable var darkroom = darkroom
        ZStack {
            PhotoCanvas(
                image: editor.showsOriginal ? editor.original : editor.preview ?? editor.original,
                // Room for the tallest panel, so the photo stays put as tools change.
                insets: UIEdgeInsets(top: 4, left: 0, bottom: (controlsHeight + Self.tallestPanel - panelHeight(for: effect)).rounded() + 8, right: 0),
                geometry: canvas,
                onPressing: { editor.showsOriginal = $0 },
                onDisplaySize: { editor.setDisplaySize(longEdge: $0) }
            )

            if let center = centerKeys, darkroom.recipe[keyPath: effect.isEnabled], !editor.showsOriginal {
                CenterHandle(
                    title: effect.title,
                    geometry: canvas,
                    center: Binding {
                        CGPoint(x: darkroom.recipe[keyPath: center.x], y: darkroom.recipe[keyPath: center.y])
                    } set: { point in
                        darkroom.recipe[keyPath: center.x] = point.x
                        darkroom.recipe[keyPath: center.y] = point.y
                    },
                    recipeCenter: CGPoint(
                        x: darkroom.currentRecipe[keyPath: center.x],
                        y: darkroom.currentRecipe[keyPath: center.y]
                    )
                )
            }

            if editor.showsOriginal {
                Text("Original")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if editor.sourceURL == nil, !editor.isLoadingPhoto {
                ContentUnavailableView {
                    Label("No Photo", systemImage: "photo")
                } actions: {
                    PhotosPicker("Choose Photo", selection: $picked, matching: .images, preferredItemEncoding: .current)
                        .buttonStyle(.glass)
                }
                .padding(.bottom, controlsHeight)
            } else if editor.isLoadingPhoto || (editor.preview == nil && editor.original == nil) {
                ProgressView()
                    .padding(.bottom, controlsHeight)
            }
        }
        .animation(.easeOut(duration: 0.12), value: editor.showsOriginal)
        .animation(.smooth(duration: 0.2), value: centerKeys != nil)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: editor.showsOriginal) { _, showing in showing }
    }

    /// The effect's centre, for those placed on the photo.
    private var centerKeys: (x: WritableKeyPath<FilmRecipe, Double>, y: WritableKeyPath<FilmRecipe, Double>)? {
        switch effect {
        case .vignette: (\.lightShaping.centerX, \.lightShaping.centerY)
        case .lensBlur: (\.lensBlur.focusX, \.lensBlur.focusY)
        default: nil
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            Text(isEnabled(effect) ? effect.title : "\(effect.title) · Off")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .padding(.top, 18)

            tools
                .padding(.top, 2)

            EffectPanel(effect: effect)
                .frame(height: panelHeight(for: effect))
                .padding(.top, 6)

            EditBar(picked: $picked)
                .padding(.top, 6)
        }
        .background {
            // The photo carries on under the controls, softly blurred, as in Photos.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            }
            .mask {
                // Eased over a long run, so there's no line where the blur begins.
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.04), location: 0.15),
                            .init(color: .black.opacity(0.15), location: 0.3),
                            .init(color: .black.opacity(0.35), location: 0.45),
                            .init(color: .black.opacity(0.6), location: 0.6),
                            .init(color: .black.opacity(0.82), location: 0.75),
                            .init(color: .black.opacity(0.96), location: 0.9),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: Self.blurFade)
                    Rectangle()
                }
            }
            // Begins a little above the controls, over the photo.
            .padding(.top, -Self.blurLeadIn)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
        .animation(.smooth(duration: 0.2), value: effect)
        // A tool palette, like Photos': text grows only so far before it would crowd the photo.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var tools: some View {
        HStack(spacing: 0) {
            ForEach(EditEffect.allCases) { candidate in
                if candidate != EditEffect.allCases.first {
                    Spacer(minLength: 0)
                }
                let isEnabled = isEnabled(candidate)
                let isModified = candidate.isModified(darkroom.recipe, from: darkroom.currentRecipe)
                ToolTab(
                    effect: candidate,
                    isSelected: candidate == effect,
                    isEnabled: isEnabled,
                    isModified: isModified
                ) {
                    // As in Photos: the first tap picks a tool, the next turns it on or off.
                    if candidate == effect {
                        toggle(candidate)
                    } else {
                        withAnimation(.smooth(duration: 0.25)) { effect = candidate }
                    }
                }
                .contextMenu {
                    Button(isEnabled ? "Turn Off" : "Turn On", systemImage: "power") {
                        toggle(candidate)
                    }
                    Button("Reset \(candidate.title)", systemImage: "arrow.uturn.backward") {
                        withAnimation(.smooth) { candidate.reset(&darkroom.recipe, to: darkroom.currentRecipe) }
                    }
                    .disabled(!isModified)
                }
                .accessibilityAction(named: isEnabled ? "Turn Off" : "Turn On") { toggle(candidate) }
            }
        }
        .padding(.horizontal, 20)
        .sensoryFeedback(.impact(weight: .light), trigger: darkroom.recipe[keyPath: effect.isEnabled])
    }

    /// How far above the controls their blur starts to fade in, and over
    /// how long it does.
    private static let blurLeadIn: CGFloat = 20
    private static let blurFade: CGFloat = 84

    /// Film Tone's stocks and its first two sliders; two sliders for the rest.
    private static let tallestPanel: CGFloat = 160

    private func panelHeight(for effect: EditEffect) -> CGFloat {
        effect.hasStock ? Self.tallestPanel : 96
    }

    private func isEnabled(_ effect: EditEffect) -> Bool {
        darkroom.recipe[keyPath: effect.isEnabled]
    }

    private func toggle(_ effect: EditEffect) {
        withAnimation(.smooth(duration: 0.25)) {
            darkroom.recipe[keyPath: effect.isEnabled].toggle()
        }
    }
}

// MARK: - Effect panel

/// The chosen effect's adjustments: Film Tone's stocks, then a line for each.
private struct EffectPanel: View {
    @Environment(Darkroom.self) private var darkroom
    @Environment(Editor.self) private var editor
    let effect: EditEffect

    var body: some View {
        @Bindable var darkroom = darkroom
        ScrollView {
            VStack(spacing: 0) {
                if effect.hasStock {
                    StockStrip(stock: stockBinding, thumbnails: editor.stockThumbnails)
                        .padding(.horizontal, -20)
                        .padding(.top, 2)
                        .padding(.bottom, 6)
                }
                ForEach(effect.parameters) { parameter in
                    ParameterSlider(
                        parameter: parameter,
                        value: $darkroom.recipe[dynamicMember: parameter.value],
                        recipeValue: darkroom.currentRecipe[keyPath: parameter.value],
                        onBegin: enable
                    )
                    .disabled(effect.hasStock && parameter.id == "Amount" && darkroom.recipe.tone.stock == .none)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, effect.hasStock ? 14 : 0)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .mask {
            // Film Tone's list fades out where it carries on below.
            LinearGradient(
                stops: [.init(color: .black, location: 0.8), .init(color: .black.opacity(effect.hasStock ? 0 : 1), location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .opacity(darkroom.recipe[keyPath: effect.isEnabled] ? 1 : 0.5)
        .id(effect)
        .transition(.opacity)
    }

    private var stockBinding: Binding<FilmStockID> {
        Binding {
            darkroom.recipe.tone.stock
        } set: { stock in
            darkroom.recipe.tone.stock = stock
            // Choosing a stock is a request to see it.
            if stock != .none {
                darkroom.recipe.tone.isEnabled = true
            }
        }
    }

    /// Adjusting an effect that's off turns it on, so the change can be seen.
    private func enable() {
        guard !darkroom.recipe[keyPath: effect.isEnabled] else { return }
        withAnimation(.smooth) { darkroom.recipe[keyPath: effect.isEnabled] = true }
    }
}

// MARK: - Bar

/// Another photo, the loaded recipe, and Save.
private struct EditBar: View {
    @Environment(Darkroom.self) private var darkroom
    @Environment(Editor.self) private var editor
    @Binding var picked: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $picked, matching: .images, preferredItemEncoding: .current) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Choose Photo")

            Spacer(minLength: 0)

            RecipeMenu {
                HStack(spacing: 9) {
                    FilmCanisterView(
                        style: CanisterStyle(recipe: darkroom.currentRecipe, isModified: darkroom.isRecipeModified),
                        recipeName: darkroom.recipeDisplayName,
                        height: 30,
                        castsShadow: false
                    )
                    .frame(width: CanisterGeometry.width * 30 / CanisterGeometry.height, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(darkroom.recipeDisplayName)
                            .font(.subheadline.weight(.semibold))
                        if darkroom.isRecipeModified {
                            Text(darkroom.currentRecipe.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 12)
                .padding(.trailing, 14)
                .frame(height: 44)
                .contentShape(Capsule())
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .animation(.smooth, value: darkroom.isRecipeModified)

            Spacer(minLength: 0)

            Button {
                Task { await editor.save() }
            } label: {
                ZStack {
                    switch editor.saveState {
                    case .idle:
                        Image(systemName: "arrow.down.to.line")
                    case .saving:
                        ProgressView()
                            .tint(.black)
                    case .saved:
                        Image(systemName: "checkmark")
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.black)
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .buttonBorderShape(.circle)
            .disabled(editor.sourceURL == nil || editor.saveState == .saving)
            .animation(.smooth, value: editor.saveState)
            .sensoryFeedback(.success, trigger: editor.saveState) { _, state in state == .saved }
            .accessibilityLabel(editor.saveState == .saved ? "Saved to Photos" : "Save to Photos")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}
