import GranularCore
import PhotosUI
import SwiftUI

struct EditView: View {
    @Environment(Darkroom.self) private var darkroom
    @Environment(Editor.self) private var editor

    @State private var effect = EditEffect.tone
    @State private var picked: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            PhotoPreview(picked: $picked)
                .padding(.horizontal, 16)

            EffectPanel(effect: effect)
                .frame(height: 196)
                .padding(.top, 12)

            dials
                .padding(.top, 10)
                .padding(.bottom, 6)

            EditBar(picked: $picked)
        }
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

    private var dials: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(EditEffect.allCases) { candidate in
                    let isEnabled = darkroom.recipe[keyPath: candidate.isEnabled]
                    let isModified = candidate.isModified(darkroom.recipe, from: darkroom.currentRecipe)
                    EffectDial(
                        effect: candidate,
                        isSelected: candidate == effect,
                        isEnabled: isEnabled,
                        strength: candidate.strength(in: darkroom.recipe),
                        isModified: isModified
                    ) {
                        withAnimation(.smooth(duration: 0.25)) { effect = candidate }
                    }
                    .frame(maxWidth: .infinity)
                    .contextMenu {
                        Button(isEnabled ? "Turn Off" : "Turn On", systemImage: "power") {
                            withAnimation(.smooth) { darkroom.recipe[keyPath: candidate.isEnabled].toggle() }
                        }
                        Button("Reset \(candidate.title)", systemImage: "arrow.uturn.backward") {
                            withAnimation(.smooth) { candidate.reset(&darkroom.recipe, to: darkroom.currentRecipe) }
                        }
                        .disabled(!isModified)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Effect panel

/// The selected effect, as on the Mac's inspector cards: its name, a reset
/// and an on/off switch, then its adjustments.
private struct EffectPanel: View {
    @Environment(Darkroom.self) private var darkroom
    @Environment(Editor.self) private var editor
    let effect: EditEffect

    var body: some View {
        @Bindable var darkroom = darkroom
        let isEnabled = darkroom.recipe[keyPath: effect.isEnabled]
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(effect.title)
                    .font(.headline)
                    .contentTransition(.opacity)
                Spacer()
                Button("Reset \(effect.title)", systemImage: "arrow.uturn.backward") {
                    withAnimation(.smooth) { effect.reset(&darkroom.recipe, to: darkroom.currentRecipe) }
                }
                .labelStyle(.iconOnly)
                .disabled(!effect.isModified(darkroom.recipe, from: darkroom.currentRecipe))
                Toggle(effect.title, isOn: $darkroom.recipe[dynamicMember: effect.isEnabled].animation(.smooth))
                    .labelsHidden()
            }
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 14) {
                    if effect.hasStock {
                        StockStrip(stock: stockBinding, thumbnails: editor.stockThumbnails)
                            .padding(.horizontal, -20)
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
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .mask {
                // The list fades out where it carries on below.
                LinearGradient(
                    stops: [.init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .scrollIndicatorsFlash(trigger: effect)
            .scrollBounceBehavior(.basedOnSize)
            .opacity(isEnabled ? 1 : 0.5)
            .id(effect)
        }
        .animation(.smooth(duration: 0.2), value: effect)
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

// MARK: - Preview

/// The photo as developed. Holding it shows the original.
private struct PhotoPreview: View {
    @Environment(Editor.self) private var editor
    @Binding var picked: PhotosPickerItem?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        @Bindable var editor = editor
        ZStack {
            Color.clear

            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 40) {
                    } onPressingChanged: { isPressing in
                        editor.showsOriginal = isPressing
                    }
                    .overlay(alignment: .topLeading) {
                        if editor.showsOriginal {
                            Text("Original")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassEffect(.regular, in: .capsule)
                                .padding(10)
                                .transition(.opacity)
                        }
                    }
                    .accessibilityLabel(editor.showsOriginal ? "Original photo" : "Edited photo")
                    .accessibilityAction(named: "Show Original") { editor.showsOriginal.toggle() }
                    .transition(.opacity)
            } else if editor.sourceURL == nil, !editor.isLoadingPhoto {
                ContentUnavailableView {
                    Label("No Photo", systemImage: "photo")
                } actions: {
                    PhotosPicker("Choose Photo", selection: $picked, matching: .images, preferredItemEncoding: .current)
                        .buttonStyle(.glassProminent)
                }
                .transition(.opacity)
            }

            if editor.isLoadingPhoto || (editor.sourceURL != nil && image == nil) {
                ProgressView()
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            max(proxy.size.width, proxy.size.height)
        } action: { longEdge in
            editor.setDisplaySize(longEdge: longEdge * displayScale)
        }
        .animation(.easeOut(duration: 0.12), value: editor.showsOriginal)
        .animation(.easeOut(duration: 0.3), value: image == nil)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: editor.showsOriginal) { _, showing in showing }
    }

    private var image: CGImage? {
        editor.showsOriginal ? editor.original : editor.preview ?? editor.original
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
                            .tint(.white)
                    case .saved:
                        Image(systemName: "checkmark")
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(editor.sourceURL == nil || editor.saveState == .saving)
            .animation(.smooth, value: editor.saveState)
            .sensoryFeedback(.success, trigger: editor.saveState) { _, state in state == .saved }
            .accessibilityLabel(editor.saveState == .saved ? "Saved to Photos" : "Save to Photos")
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
    }
}
