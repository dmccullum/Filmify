import SwiftUI

enum CameraMode: String {
    case instant
    case edit
}

/// The camera back: the nameplate and mode switch along the top, and below
/// them Instant's film chamber or Edit's darkroom. Edit gives the photo the
/// whole screen; its switch moves up beside the Dynamic Island.
struct CameraView: View {
    @Environment(Darkroom.self) private var darkroom
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("mode") private var mode = CameraMode.instant
    /// Edit's controls are only built once they've been asked for.
    @State private var hasEdited = false
    @State private var safeAreaTop: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var switchSize = CGSize(width: 84, height: 32)

    private static let headerRow: CGFloat = 32
    private static let headerHeight: CGFloat = 4 + headerRow + 12

    var body: some View {
        ZStack(alignment: .top) {
            InstantView()
                .padding(.top, Self.headerHeight)
                .modeVisibility(mode == .instant)
            if hasEdited || mode == .edit {
                EditView()
                    .padding(.top, switchFitsInStatusBar ? 0 : Self.headerHeight)
                    .modeVisibility(mode == .edit)
            }
            header
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { safeAreaTop = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background {
            // Instant is the camera back; Edit is plain, like the Mac's.
            ZStack {
                Color(.systemBackground)
                AlloySurface()
                    .opacity(mode == .instant ? 1 : 0)
            }
            .ignoresSafeArea()
        }
        .statusBarHidden(isEditingFullScreen)
        // Editors are dark, so the photo is what's bright.
        .preferredColorScheme(mode == .edit ? .dark : nil)
        .sensoryFeedback(.selection, trigger: mode)
        .onChange(of: mode, initial: true) { _, mode in
            if mode == .edit { hasEdited = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { darkroom.persistRecipe() }
        }
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            CameraNameplate()
                .frame(height: Self.headerRow)
                .padding(.leading, 22)
                .padding(.top, 4)
                .opacity(mode == .instant ? 1 : 0)
                .allowsHitTesting(mode == .instant)
                .accessibilityHidden(mode != .instant)

            history
                .padding(.top, switchCenterY - switchSize.height / 2)
                .padding(.leading, 16 + (isEditingFullScreen ? statusBarInset : 0))
                .ignoresSafeArea(edges: .top)
                .opacity(mode == .edit ? 1 : 0)
                .allowsHitTesting(mode == .edit)
                .accessibilityHidden(mode != .edit)

            modeSwitch
                // Laid out rather than offset, so it's touched where it's drawn.
                .padding(.top, switchCenterY - switchSize.height / 2)
                .padding(.trailing, 16 + (isEditingFullScreen ? statusBarInset : 0))
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var modeSwitch: some View {
        Picker("Mode", selection: $mode.animation(.smooth(duration: 0.3))) {
            // Symbols, so the switch fits beside the Dynamic Island.
            Image(systemName: "film.stack")
                .accessibilityLabel("Instant")
                .tag(CameraMode.instant)
            Image(systemName: "slider.horizontal.3")
                .accessibilityLabel("Edit")
                .tag(CameraMode.edit)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        // Any tap flips it, even on the mode already chosen.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay {
            Button {
                withAnimation(.smooth(duration: 0.3)) { mode = mode == .instant ? .edit : .instant }
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mode")
            .accessibilityValue(mode == .instant ? "Instant" : "Edit")
            .accessibilityHint("Switches to \(mode == .instant ? "Edit" : "Instant")")
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { switchSize = $0 }
    }

    /// Undo and Redo for the look, mirroring the mode switch across the
    /// Dynamic Island.
    private var history: some View {
        HStack(spacing: 0) {
            historyButton("Undo", systemImage: "arrow.uturn.backward", isAvailable: darkroom.canUndo, action: darkroom.undo)
            historyButton("Redo", systemImage: "arrow.uturn.forward", isAvailable: darkroom.canRedo, action: darkroom.redo)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func historyButton(_ title: String, systemImage: String, isAvailable: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.smooth) { action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isAvailable ? .primary : .tertiary)
                .frame(width: switchSize.width / 2, height: switchSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel(title)
    }

    /// From the top of the screen: in the header beside the nameplate, or
    /// level with the Dynamic Island, where the battery was.
    private var switchCenterY: CGFloat {
        isEditingFullScreen ? safeAreaTop / 2 : safeAreaTop + 4 + Self.headerRow / 2
    }

    /// Phones with a notch or Dynamic Island have room beside it once the
    /// status bar is hidden; others keep the header.
    private var switchFitsInStatusBar: Bool { safeAreaTop >= 44 }

    private var isEditingFullScreen: Bool { mode == .edit && switchFitsInStatusBar }

    /// How much further in than the header's margin the switch sits to be
    /// centred in the space beside the Dynamic Island, as the status bar's
    /// own items are.
    private var statusBarInset: CGFloat {
        let island: CGFloat = 126
        let center = (width - island) / 4
        return max(0, center - switchSize.width / 2 - 16)
    }
}

private extension View {
    /// Both modes stay built, so Instant's film keeps its place while editing.
    func modeVisibility(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.985)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}
