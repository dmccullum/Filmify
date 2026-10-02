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
            Image(systemName: "camera")
                .accessibilityLabel("Instant")
                .tag(CameraMode.instant)
            Image(systemName: "slider.horizontal.3")
                .accessibilityLabel("Edit")
                .tag(CameraMode.edit)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { switchSize = $0 }
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
