import SwiftUI

enum CameraMode: String {
    case instant
    case edit
}

/// The camera back: the nameplate and mode switch along the top, and below
/// them Instant's film chamber or Edit's darkroom.
struct CameraView: View {
    @Environment(Darkroom.self) private var darkroom
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("mode") private var mode = CameraMode.instant
    /// Edit's controls are only built once they've been asked for.
    @State private var hasEdited = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CameraNameplate()
                Spacer(minLength: 16)
                Picker("Mode", selection: $mode.animation(.smooth(duration: 0.3))) {
                    Text("Instant").tag(CameraMode.instant)
                    Text("Edit").tag(CameraMode.edit)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(.leading, 22)
            .padding(.trailing, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)

            ZStack {
                InstantView()
                    .modeVisibility(mode == .instant)
                if hasEdited || mode == .edit {
                    EditView()
                        .modeVisibility(mode == .edit)
                }
            }
        }
        .background {
            // Instant is the camera back; Edit is plain, like the Mac's.
            ZStack {
                Color(.systemBackground)
                AlloySurface()
                    .opacity(mode == .instant ? 1 : 0)
            }
            .ignoresSafeArea()
        }
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
