import AppKit
import GranularCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct DropModeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The job currently sitting in the gate. It stays there for a beat after
    /// finishing so the exposure reads before the film advances.
    @State private var exposure: Exposure?
    /// Film position in frames, animated from -1 to 0 each time the film winds on.
    @State private var advance: CGFloat = 0
    @State private var isAdvancing = false
    /// Film loading, played when Instant mode settles and reversed when leaving it.
    @State private var isCanisterSeated = false
    @State private var filmOut: CGFloat = 0
    @FocusState private var isStripFocused: Bool
    @State private var rightClickMonitor: Any?
    private var roll: FilmRoll { .shared }
    private var preview: FramePreviewController { .shared }

    private struct Exposure: Equatable {
        let jobID: UUID
        let startedAt: Date
    }

    private struct LeadJobKey: Equatable {
        let id: UUID?
        let state: JobState?
    }

    var body: some View {
        VStack(spacing: 0) {
            FilmChamber(
                style: CanisterStyle(recipe: model.currentRecipe, isModified: model.isRecipeModified),
                recipeName: model.recipeDisplayName,
                gate: exposure.map { exposure in
                    let isSpoiled = if case .failed = model.job(exposure.jobID)?.state { true } else { false }
                    return GateExposure(id: exposure.jobID, image: roll.thumbnails[exposure.jobID]?.image, isSpoiled: isSpoiled)
                },
                frames: exposedFrames,
                selectedFrameID: roll.selectedFrameID,
                isStripFocused: isStripFocused,
                advance: advance,
                isAdvancing: isAdvancing,
                framesWound: roll.framesWound,
                isCanisterSeated: isCanisterSeated,
                filmOut: filmOut,
                isTargeted: model.isDropTargeted,
                reduceMotion: reduceMotion,
                onCanister: { RecipeMenuPresenter.popUp(model: model) },
                onChoose: { model.chooseImagesForDroplet() },
                onSelect: { selectFrame($0) }
            )
            .focusable(!exposedFrames.isEmpty)
            .focused($isStripFocused)
            .focusEffectDisabled()
            .onKeyPress(.space) {
                guard roll.selectedFrameID != nil else { return .ignored }
                preview.togglePanel()
                return .handled
            }
            .onKeyPress(.leftArrow) {
                preview.moveSelection(by: -1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                preview.moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.escape) {
                guard roll.selectedFrameID != nil else { return .ignored }
                roll.selectedFrameID = nil
                return .handled
            }
            .onKeyPress(keys: [.delete]) { press in
                guard press.modifiers == .command, let selected = roll.selectedFrameID else { return .ignored }
                model.moveOutputToTrash(of: selected)
                return .handled
            }
            .onCopyCommand {
                guard let url = exposedFrames.first(where: { $0.id == roll.selectedFrameID })?.outputURL else { return [] }
                return [OutputFile.itemProvider(for: url)]
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)

            FilmBackStatusBar()
        }
        .background(AlloySurface().ignoresSafeArea())
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            // A frame dragged off the strip and let go over the window stays put.
            let urls = urls.filter { !model.isInstantOutput($0) }
            guard !urls.isEmpty else { return false }
            Task { await model.processInstantly(urls) }
            return true
        } isTargeted: { targeted in
            // A frame being dragged out of the strip isn’t something to release into the gate.
            withAnimation(.easeOut(duration: 0.16)) {
                model.isDropTargeted = targeted && !roll.isDraggingFrame
            }
        }
        .onChange(of: LeadJobKey(id: model.jobs.first?.id, state: model.jobs.first?.state)) { _, _ in
            leadJobChanged()
        }
        .onChange(of: exposedFrames, initial: true) { _, frames in
            framesChanged(frames)
        }
        .onChange(of: roll.selectedFrameID) { _, _ in
            preview.selectionDidChange()
        }
        .onAppear {
            if model.isFilmLoaded {
                isCanisterSeated = true
                filmOut = 1
            }
            selectFramesOnRightClick()
        }
        .onDisappear {
            if let rightClickMonitor {
                NSEvent.removeMonitor(rightClickMonitor)
            }
            rightClickMonitor = nil
        }
        .onChange(of: model.isFilmLoaded) { _, isLoaded in
            if isLoaded {
                loadFilm()
            } else {
                rewindFilm()
            }
        }
    }

    /// The canister drops into its pocket, then the film pulls out across the gate.
    private func loadFilm() {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) {
                isCanisterSeated = true
                filmOut = 1
            }
            return
        }
        // Runs alongside the window settling, on the same curve.
        withAnimation(.spring(duration: 0.46, bounce: 0.14)) {
            isCanisterSeated = true
        }
        withAnimation(AppModel.modeTransitionAnimation.delay(0.08)) {
            filmOut = 1
        }
    }

    /// The film winds back into the canister, then the canister lifts out.
    private func rewindFilm() {
        guard !reduceMotion else {
            withAnimation(.easeIn(duration: 0.15)) {
                isCanisterSeated = false
                filmOut = 0
            }
            return
        }
        withAnimation(.easeIn(duration: 0.26)) {
            filmOut = 0
        }
        withAnimation(.easeIn(duration: 0.24).delay(0.1)) {
            isCanisterSeated = false
        }
    }

    private var exposedFrames: [ExposedFrame] {
        model.jobs.compactMap { job -> ExposedFrame? in
            guard job.id != exposure?.jobID else { return nil }
            let development: ExposedFrame.Development
            switch job.state {
            case .finished(let outputURL): development = .developed(outputURL)
            case .failed(let message): development = .spoiled(message)
            case .queued, .processing: return nil
            }
            return ExposedFrame(
                id: job.id,
                image: roll.thumbnails[job.id]?.image,
                sourceURL: job.sourceURL,
                development: development,
                isUnsaved: model.unsavedJobIDs.contains(job.id)
            )
        }
        .prefix(4)
        .map { $0 }
    }

    /// Clicking a frame selects it and gives the strip keyboard focus, for
    /// Space to Quick Look and the arrow keys to move along the film.
    private func selectFrame(_ id: UUID) {
        roll.selectedFrameID = id
        isStripFocused = true
    }

    /// A right-click (or Control-click) marks the frame under the pointer before
    /// its menu opens, as in Finder, so the menu and the mark agree.
    private func selectFramesOnRightClick() {
        guard rightClickMonitor == nil else { return }
        let focus = $isStripFocused
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                  let contentView = event.window?.contentView else { return event }
            let point = contentView.convert(event.locationInWindow, from: nil)
            // Frame rects are kept top-left, the way SwiftUI reports them.
            let inWindow = CGPoint(x: point.x, y: contentView.bounds.height - point.y)
            MainActor.assumeIsolated {
                let preview = FramePreviewController.shared
                let onStrip = Set(preview.frames.map(\.id))
                if let hit = preview.frameRects.first(where: { onStrip.contains($0.key) && $0.value.contains(inWindow) }) {
                    FilmRoll.shared.selectedFrameID = hit.key
                    focus.wrappedValue = true
                }
            }
            return event
        }
    }

    private func framesChanged(_ frames: [ExposedFrame]) {
        preview.frames = frames.map { frame in
            PreviewFrame(id: frame.id, url: frame.outputURL ?? frame.sourceURL, image: frame.image)
        }
        if let selected = roll.selectedFrameID, !frames.contains(where: { $0.id == selected }) {
            roll.selectedFrameID = nil
        }
        // A frame trashed from the strip lets an older one back on, which may
        // have lost its thumbnail along the way.
        for frame in frames where frame.image == nil && !roll.loading.contains(frame.id) {
            loadThumbnail(from: frame.outputURL ?? frame.sourceURL, for: frame.id)
        }
    }

    private func leadJobChanged() {
        guard let job = model.jobs.first else { return }
        switch job.state {
        case .queued:
            break
        case .processing:
            guard exposure?.jobID != job.id else { return }
            withAnimation(.spring(duration: 0.55)) {
                exposure = Exposure(jobID: job.id, startedAt: .now)
            }
            loadThumbnail(from: job.sourceURL, for: job.id)
        case .finished(let output):
            loadThumbnail(from: output, for: job.id)
            advanceFilm(after: job.id)
        case .failed:
            // The spoiled frame fogs in the gate, then winds on like any other.
            advanceFilm(after: job.id)
        }
    }

    private func advanceFilm(after jobID: UUID) {
        guard let exposure, exposure.jobID == jobID else { return }
        let hold = reduceMotion ? 0.4 : 1.6
        let remaining = hold - Date.now.timeIntervalSince(exposure.startedAt)
        Task {
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard self.exposure?.jobID == jobID else { return }
            windOn()
        }
    }

    /// Winds the film on one frame: the exposed frame moves out of the gate
    /// and the whole strip, perforations and edge print included, travels with it.
    private func windOn() {
        var jump = Transaction()
        jump.disablesAnimations = true
        withTransaction(jump) {
            exposure = nil
            advance = -1
            isAdvancing = true
            roll.framesWound += 1
        }
        Task {
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.9)) {
                advance = 0
            } completion: {
                isAdvancing = false
                // Not while a later frame is already in the gate.
                if exposure == nil { model.filmDidSettle() }
            }
        }
    }

    private func loadThumbnail(from url: URL, for jobID: UUID) {
        roll.loading.insert(jobID)
        Task {
            defer { roll.loading.remove(jobID) }
            guard let thumbnail = await FilmThumbnail.load(url) else { return }
            let visible = Set(model.jobs.prefix(6).map(\.id)).union(exposedFrames.map(\.id))
            // One assignment, so the strip redraws once for the new thumbnail and the dropped ones.
            var thumbnails = roll.thumbnails
            thumbnails[jobID] = thumbnail
            roll.thumbnails = thumbnails.filter { visible.contains($0.key) }
        }
    }
}

// MARK: - Thumbnails

/// Thumbnails of the frames on the strip. Lives outside the view so the
/// negatives survive a trip to Edit mode and back.
@MainActor
@Observable
final class FilmRoll {
    static let shared = FilmRoll()
    var thumbnails: [UUID: FilmThumbnail] = [:]
    /// How many frames have been wound on, so the edge numbers travel with the film.
    var framesWound = 0
    /// The frame marked on the strip, for Quick Look and the context actions.
    var selectedFrameID: UUID?
    @ObservationIgnored var loading: Set<UUID> = []
    /// True while one of the strip’s own frames is being dragged, so the gate
    /// doesn’t offer to develop it again.
    @ObservationIgnored var isDraggingFrame = false
}

struct FilmThumbnail: @unchecked Sendable {
    let image: CGImage

    static func load(_ url: URL, maxPixelSize: Int = 720) async -> FilmThumbnail? {
        await Task.detached(priority: .userInitiated) {
            let gainedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gainedAccess { url.stopAccessingSecurityScopedResource() }
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return FilmThumbnail(image: image)
        }.value
    }
}

struct GateExposure: Equatable {
    let id: UUID
    let image: CGImage?
    /// The image failed, so the exposure fogs instead of burning in.
    var isSpoiled = false
}

struct ExposedFrame: Identifiable, Equatable {
    enum Development: Equatable {
        case developed(URL)
        /// Light-struck: processing failed, with the reason.
        case spoiled(String)
    }

    let id: UUID
    let image: CGImage?
    let sourceURL: URL
    let development: Development
    /// Developed into a temporary folder, waiting for the person to say where it goes.
    var isUnsaved = false

    var outputURL: URL? {
        if case .developed(let url) = development { return url }
        return nil
    }
}

// MARK: - Chamber

private struct FilmChamber: View {
    let style: CanisterStyle
    let recipeName: String
    let gate: GateExposure?
    let frames: [ExposedFrame]
    let selectedFrameID: UUID?
    let isStripFocused: Bool
    let advance: CGFloat
    let isAdvancing: Bool
    let framesWound: Int
    let isCanisterSeated: Bool
    let filmOut: CGFloat
    let isTargeted: Bool
    let reduceMotion: Bool
    let onCanister: () -> Void
    let onChoose: () -> Void
    let onSelect: (UUID) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let format = style.format
            // Size everything from the Instant window's chamber, not the live
            // height, so nothing balloons while the window resizes between modes.
            let layoutHeight = min(height, 310)
            let g = CanisterGeometry.self
            let canisterHeight = layoutHeight - 30
            let scale = canisterHeight / g.height
            let canisterWidth = g.width * scale
            let canisterLeading: CGFloat = 20
            let canisterTop = (height - canisterHeight) / 2
            let bodyTrailing = canisterLeading + canisterWidth
            // The film comes out from under the lip, as tall as the body and
            // nearly flush with its top, like a real canister.
            let bodyHeight = g.bodyHeight * scale
            let stripHeight = (bodyHeight * g.filmToBody).rounded()
            let stripTop = canisterTop + g.topCap * scale + (bodyHeight - stripHeight) * 0.25
            let stripLeading = canisterLeading + (2 + g.bodyWidth - g.lipWidth / 2) * scale
            let stripWidth = width - stripLeading

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: 0x0A0A0A))
                    .shadow(color: .white.opacity(0.04), radius: 0, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.black, lineWidth: 8)
                            .blur(radius: 6)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            // The sunk edge never changes while the film moves; draw it once.
                            .drawingGroup()
                    )
                    .frame(width: bodyTrailing + 4, height: canisterHeight + 18)
                    .offset(x: 8, y: canisterTop - 9)

                let curlStart = width - FilmStrip.curlWidth(for: stripWidth)

                takeUpSlot(leading: curlStart - 14, width: width, top: stripTop - 9, height: stripHeight + 18)

                rail(y: stripTop - 9, from: stripLeading + 30, to: curlStart - 18)
                rail(y: stripTop + stripHeight + 5, from: stripLeading + 30, to: curlStart - 18)

                FilmStrip(
                    format: format,
                    recipeName: recipeName,
                    gate: gate,
                    frames: frames,
                    selectedFrameID: selectedFrameID,
                    isStripFocused: isStripFocused,
                    advance: advance,
                    isAdvancing: isAdvancing,
                    framesWound: framesWound,
                    isTargeted: isTargeted,
                    reduceMotion: reduceMotion,
                    onChoose: onChoose,
                    onSelect: onSelect
                )
                .frame(width: stripWidth, height: stripHeight)
                // Loading: the film slides out of the canister's lip toward the take-up.
                .offset(x: -(1 - filmOut) * 60)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: stripWidth * filmOut)
                }
                .allowsHitTesting(filmOut == 1)
                .offset(x: stripLeading, y: stripTop)

                if isTargeted {
                    RadialGradient(
                        colors: [FilmBackPalette.signal.opacity(0.26), FilmBackPalette.signal.opacity(0)],
                        center: UnitPoint(x: 0.45, y: 0.5),
                        startRadius: 0,
                        endRadius: width * 0.45
                    )
                    .allowsHitTesting(false)
                }

                if let gate, !reduceMotion {
                    ChamberFlash(center: UnitPoint(x: (stripLeading + stripHeight * 0.6) / width, y: (stripTop + stripHeight / 2) / height))
                        .id(gate.id)
                        .allowsHitTesting(false)
                }

                Button(action: onCanister) {
                    FilmCanisterView(style: style, recipeName: recipeName, height: canisterHeight)
                        .frame(width: canisterWidth, height: canisterHeight)
                }
                .buttonStyle(CanisterButtonStyle())
                .help("Choose or save a film recipe")
                .accessibilityLabel("Recipe: \(recipeName)")
                .accessibilityHint("Shows the recipe menu")
                .offset(y: isCanisterSeated ? 0 : -canisterHeight * 0.4)
                .scaleEffect(isCanisterSeated ? 1 : 1.04)
                .opacity(isCanisterSeated ? 1 : 0)
                .id(style)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .offset(x: canisterLeading, y: canisterTop)
            }
            .animation(.spring(duration: 0.45, bounce: 0.18), value: style)
        }
        .background(
            RadialGradient(
                colors: [Color(hex: 0x262523), Color(hex: 0x151514), Color(hex: 0x0B0B0B)],
                center: UnitPoint(x: 0.5, y: 0.45),
                startRadius: 0,
                endRadius: 520
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.black.opacity(0.9), lineWidth: 10)
                .blur(radius: 7)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .drawingGroup()
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.black.opacity(0.55), .white.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
    }

    /// The opening the film curls into on its way to the take-up spool, sunk
    /// like the canister bay so the strip reads as going into the body.
    private func takeUpSlot(leading: CGFloat, width: CGFloat, top: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(hex: 0x0A0A0A))
            .shadow(color: .white.opacity(0.04), radius: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.black, lineWidth: 8)
                    .blur(radius: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .drawingGroup()
            )
            // Runs off the chamber's right edge, which clips it.
            .frame(width: width - leading + 20, height: height)
            .offset(x: leading, y: top)
    }

    private func rail(y: CGFloat, from start: CGFloat, to end: CGFloat) -> some View {
        Capsule()
            .fill(LinearGradient(colors: [Color(hex: 0xECEEF0), Color(hex: 0x8D9296), Color(hex: 0x5A5E62)], startPoint: .top, endPoint: .bottom))
            .frame(width: max(0, end - start), height: 4)
            .shadow(color: .black.opacity(0.7), radius: 2, y: 2)
            .offset(x: start, y: y)
    }
}

private struct ChamberFlash: View {
    let center: UnitPoint
    @State private var opacity = 1.0

    var body: some View {
        RadialGradient(
            colors: [Color(hex: 0xFFF8EC).opacity(0.6), Color(hex: 0xFFF8EC).opacity(0)],
            center: center,
            startRadius: 0,
            endRadius: 320
        )
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { opacity = 0 }
        }
    }
}

private struct CanisterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverLift(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct HoverLift<Content: View>: View {
    let isPressed: Bool
    @ViewBuilder var content: Content
    @State private var isHovering = false

    var body: some View {
        content
            .offset(y: isHovering && !isPressed ? -3 : 0)
            .brightness(isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.18), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

// MARK: - Film strip

private struct StripMetrics {
    let bandTop: CGFloat
    let bandBottom: CGFloat
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let gap: CGFloat
    let leader: CGFloat = 38

    var pitch: CGFloat { frameWidth + gap }

    init(format: FilmFormat, height: CGFloat) {
        bandTop = (height * format.bandTop).rounded()
        bandBottom = bandTop + FilmRebate.edgePrintHeight
        frameHeight = height - bandTop - bandBottom
        frameWidth = (frameHeight * format.frameAspect).rounded()
        gap = max(8, (frameWidth * 0.06).rounded())
    }
}

/// The back of the film: dark base, perforations and edge print, running under
/// a fixed gate (the drop target). Exposed frames ride the film as it winds on,
/// and the far end curls away toward the implied take-up spool.
private struct FilmStrip: View {
    let format: FilmFormat
    let recipeName: String
    let gate: GateExposure?
    let frames: [ExposedFrame]
    let selectedFrameID: UUID?
    let isStripFocused: Bool
    let advance: CGFloat
    let isAdvancing: Bool
    let framesWound: Int
    let isTargeted: Bool
    let reduceMotion: Bool
    let onChoose: () -> Void
    let onSelect: (UUID) -> Void

    private let curlAngles: [Double] = stride(from: 4.0, through: 88, by: 4).map { $0 }

    /// How much of the strip's right end bends away behind the chamber wall.
    static func curlWidth(for width: CGFloat) -> CGFloat {
        min(30, width * 0.07)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let metrics = StripMetrics(format: format, height: height)
            let curlWidth = Self.curlWidth(for: width)
            let flatWidth = width - curlWidth
            let cosines = curlAngles.map { cos($0 * .pi / 180) }
            let segment = curlWidth / cosines.reduce(0, +)
            let contentWidth = flatWidth + segment * CGFloat(curlAngles.count)
            let pinch = curlWidth * 0.45 / max(height, 1)

            ZStack(alignment: .topLeading) {
                film(width: contentWidth, height: height, metrics: metrics, slice: nil)
                    .frame(width: flatWidth, height: height, alignment: .leading)
                    .clipped()

                ForEach(curlAngles.indices, id: \.self) { index in
                    let start = flatWidth + segment * CGFloat(index)
                    let displayX = flatWidth + segment * cosines[..<index].reduce(0, +)
                    let bend = 1 - cosines[index]
                    film(width: contentWidth, height: height, metrics: metrics, slice: start...(start + segment + 1))
                        .offset(x: -start)
                        // A point of overlap hides the seams between slices.
                        .frame(width: segment + 1, height: height, alignment: .leading)
                        .clipped()
                        // Recedes symmetrically about the strip's centre line so the
                        // film turns away behind rather than drooping. The pinch
                        // scales with the curl so the corners round off like a
                        // tight roll instead of tapering into the distance. Easing
                        // it in softens the corners without changing the total.
                        .scaleEffect(x: cosines[index], y: 1 - pow(bend, 0.75) * pinch, anchor: .leading)
                        .offset(x: displayX)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                // One continuous falloff across the curl so the segments read as a
                // bend. It starts a little before the curl so the turn eases in.
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0),
                        // A faint, wide highlight just into the bend, where the
                        // roll turns toward the light, eased on both sides.
                        .init(color: .white.opacity(0.01), location: 0.16),
                        .init(color: .white.opacity(0.022), location: 0.28),
                        .init(color: .white.opacity(0.025), location: 0.36),
                        .init(color: .white.opacity(0.01), location: 0.45),
                        .init(color: .black.opacity(0.06), location: 0.54),
                        .init(color: .black.opacity(0.18), location: 0.63),
                        .init(color: .black.opacity(0.36), location: 0.72),
                        .init(color: .black.opacity(0.6), location: 0.82),
                        .init(color: .black.opacity(0.82), location: 0.92),
                        .init(color: .black.opacity(0.95), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: curlWidth + 10, height: height)
                .offset(x: flatWidth - 8)
                .allowsHitTesting(false)

                FilmGate(
                    isEmpty: gate == nil && !isAdvancing,
                    showsPrompt: gate == nil && !isAdvancing,
                    isTargeted: isTargeted,
                    onChoose: onChoose
                )
                .frame(width: metrics.frameWidth, height: metrics.frameHeight)
                .offset(x: metrics.leader, y: metrics.bandTop)
            }
        }
    }

    /// The film itself, laid out one frame early and shifted by `advance`, so
    /// winding on is a single horizontal move of everything printed on it.
    ///
    /// The curl repeats the film once per slice, each showing a sliver of it.
    /// `slice` is that sliver’s span across the film; what lies outside it is
    /// never seen, so it isn’t drawn: without this every frame, blur and edge
    /// number would be rendered two dozen times over.
    private func film(width: CGFloat, height: CGFloat, metrics: StripMetrics, slice: ClosedRange<CGFloat>?) -> some View {
        let isPrimary = slice == nil
        let pitch = metrics.pitch
        // While it winds on the film sits between one and two pitches left of
        // where it is laid out, so a sliver can show anything in that reach.
        let reach: ClosedRange<CGFloat>? = slice.map { ($0.lowerBound + pitch - 16)...($0.upperBound + 2 * pitch + 16) }
        // One frame of slack at each end so the strip never runs short mid-wind.
        let filmWidth = width + 2 * pitch
        let blankCount = max(0, Int(ceil((filmWidth - metrics.leader) / pitch)) - 2 - frames.count)
        let slot = CGSize(width: metrics.frameWidth, height: metrics.frameHeight)

        return ZStack(alignment: .topLeading) {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x1A120D), location: 0),
                    .init(color: Color(hex: 0x2A1C14), location: 0.16),
                    .init(color: Color(hex: 0x33231A), location: 0.5),
                    .init(color: Color(hex: 0x2A1C14), location: 0.84),
                    .init(color: Color(hex: 0x1A120D), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                FilmRebate(
                    width: filmWidth,
                    height: metrics.bandTop,
                    perforated: format.perforatedTop,
                    perforationsPerFrame: format.perforationsPerFrame,
                    pitch: pitch,
                    leader: metrics.leader,
                    edgePrint: nil,
                    firstFrame: 0,
                    namedFrame: 0,
                    visible: reach
                )
                HStack(spacing: metrics.gap) {
                    // The frame that has just left the canister side of the gate.
                    Color.clear.frame(width: slot.width, height: slot.height)

                    Group {
                        if let gate, isPrimary {
                            ExposureBurn(
                                image: gate.image,
                                isSpoiled: gate.isSpoiled,
                                seed: FoggedFrame.seed(for: gate.id),
                                reduceMotion: reduceMotion
                            )
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .accessibilityLabel("Exposing image")
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: slot.width, height: slot.height)

                    ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                        // Frame `index` sits in the slot after the gate's, in reach of these film positions.
                        let start = metrics.leader + CGFloat(index) * pitch
                        if let slice, start - 16 > slice.upperBound || start + pitch + slot.width + 16 < slice.lowerBound {
                            Color.clear.frame(width: slot.width, height: slot.height)
                        } else {
                            StripFrame(
                                frame: frame,
                                size: slot,
                                isSelected: frame.id == selectedFrameID,
                                isStripFocused: isStripFocused,
                                // The curl only repeats the film to look at.
                                isInteractive: isPrimary,
                                onSelect: { onSelect(frame.id) }
                            )
                        }
                    }

                    ForEach(0..<blankCount, id: \.self) { _ in
                        Color.clear.frame(width: slot.width, height: slot.height)
                    }
                }
                .padding(.leading, metrics.leader)
                .frame(width: filmWidth, height: metrics.frameHeight, alignment: .leading)
                FilmRebate(
                    width: filmWidth,
                    height: metrics.bandBottom,
                    perforated: format.perforatedBottom,
                    perforationsPerFrame: format.perforationsPerFrame,
                    pitch: pitch,
                    leader: metrics.leader,
                    edgePrint: "GRANULAR \(recipeName.uppercased())",
                    // The gate holds the next frame to expose; numbers fall toward the take-up.
                    firstFrame: framesWound + 2,
                    // The film name marks the unexposed frame in the gate. The exposure
                    // flash hands it on to the next frame, which then winds into the
                    // gate carrying it, so the name never leaves with an old frame.
                    namedFrame: framesWound + (gate == nil ? 1 : 2),
                    visible: reach
                )
            }
            .frame(width: filmWidth, alignment: .leading)
            .offset(x: (advance - 1) * pitch)

            LinearGradient(colors: [.white.opacity(0.05), .white.opacity(0)], startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
    }
}

private struct FilmRebate: View {
    nonisolated static let edgePrintHeight: CGFloat = 10

    let width: CGFloat
    let height: CGFloat
    let perforated: Bool
    let perforationsPerFrame: Int
    let pitch: CGFloat
    let leader: CGFloat
    let edgePrint: String?
    /// Frame number printed at the first slot, counting down slot by slot.
    let firstFrame: Int
    /// The frame whose edge print carries the film name.
    let namedFrame: Int
    /// Where along the band anything can be seen, when only a sliver of it is.
    var visible: ClosedRange<CGFloat>?

    var body: some View {
        Canvas { context, size in
            let printHeight = edgePrint == nil ? 0 : Self.edgePrintHeight
            if perforated, perforationsPerFrame > 0 {
                let perfPitch = pitch / CGFloat(perforationsPerFrame)
                let holeWidth = min(perfPitch * 0.42, 14)
                let holeHeight = min(size.height - printHeight - 6, holeWidth * 1.65)
                let y = printHeight + (size.height - printHeight - holeHeight) / 2
                var x: CGFloat = leader * 0.5
                while x < size.width {
                    defer { x += perfPitch }
                    if let visible, x + holeWidth < visible.lowerBound || x > visible.upperBound { continue }
                    let hole = Path(roundedRect: CGRect(x: x, y: y, width: holeWidth, height: holeHeight), cornerRadius: 2)
                    context.fill(hole, with: .color(Color(hex: 0x050404)))
                    context.stroke(hole, with: .color(Color(hex: 0xFFD2AA, opacity: 0.1)), lineWidth: 0.75)
                }
            }
            if let edgePrint {
                var number = firstFrame
                var x = leader
                while x < size.width {
                    defer {
                        x += pitch
                        number -= 1
                    }
                    // Nothing is printed on the leader before frame 1.
                    guard number > 0 else { continue }
                    // The longest marker is a little under 5 pt a character.
                    if let visible, x + 4 > visible.upperBound || x + 4 + 5 * CGFloat(edgePrint.count + 12) < visible.lowerBound {
                        continue
                    }
                    let marker = number == namedFrame ? "\(edgePrint)   ▸ \(number)" : "▸ \(number)    ▸ \(number)A"
                    let text = Text(marker)
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xFFAA6E, opacity: 0.4))
                    let y = perforated ? 1 + printHeight / 2 : size.height / 2
                    context.draw(text, at: CGPoint(x: x + 4, y: y), anchor: .leading)
                }
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

/// A processed frame seen from the back of the film: mirrored, soft, and
/// toned to the brown of a developed negative.
private struct NegativeFrame: View {
    let image: CGImage?

    var body: some View {
        ZStack {
            Color(hex: 0x2B1C13)
            if let image {
                NegativeImage(image: image)
            }
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(.black.opacity(0.35), lineWidth: 1)
                .shadow(color: Color(hex: 0x140A04).opacity(0.8), radius: 8)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

private struct NegativeImage: View {
    let image: CGImage

    var body: some View {
        Color.clear
            .overlay {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .grayscale(1)
            .colorInvert()
            .colorMultiply(Color(hex: 0xC98450))
            .brightness(-0.3)
            .contrast(1.05)
            .blur(radius: 1.2)
            .opacity(0.88)
            .scaleEffect(x: -1, y: 1)
            // Toning and blur are worked out once, so a frame that only rides
            // along on the film costs one texture instead of a chain of filters.
            .drawingGroup()
    }
}

/// A spoiled frame: light got to it, so where the image should be there’s
/// an amber fog washing in from the edge. The failure itself is in its tooltip.
private struct FoggedFrame: View {
    let image: CGImage?
    let seed: UInt64

    /// The same frame fogs the same way in the gate and on the strip.
    static func seed(for id: UUID) -> UInt64 {
        UInt64(truncatingIfNeeded: id.hashValue)
    }

    var body: some View {
        ZStack {
            Color(hex: 0x2B1C13)
            if let image {
                NegativeImage(image: image)
                    .opacity(0.3)
            }
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xFFD7A0, opacity: 0.9), location: 0),
                    .init(color: Color(hex: 0xFF8A3D, opacity: 0.72), location: 0.24),
                    .init(color: Color(hex: 0xE2471B, opacity: 0.42), location: 0.52),
                    .init(color: Color(hex: 0x7A2410, opacity: 0.18), location: 0.8),
                    .init(color: Color(hex: 0x7A2410, opacity: 0), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Uneven blooms, so it reads as light leaking in rather than a gradient.
            Canvas { context, size in
                var generator = SeededGenerator(seed: seed)
                let bloom = Color(hex: 0xFFC98A)
                for _ in 0..<6 {
                    let radius = CGFloat.random(in: 0.25...0.6, using: &generator) * size.height
                    let center = CGPoint(
                        x: CGFloat.random(in: 0...size.width, using: &generator),
                        y: CGFloat.random(in: 0...size.height, using: &generator)
                    )
                    let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(
                        Path(ellipseIn: circle),
                        with: .radialGradient(
                            Gradient(colors: [bloom.opacity(0.3), bloom.opacity(0)]),
                            center: center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }
            .blendMode(.screen)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFFECDC, opacity: 0.85))
                .shadow(color: .black.opacity(0.5), radius: 2)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(.black.opacity(0.35), lineWidth: 1)
        }
        .compositingGroup()
    }
}

/// A frame on the strip. Click marks it, double-click opens the processed
/// image, drag takes the file elsewhere, and right-click has the rest.
private struct StripFrame: View {
    @Environment(AppModel.self) private var model
    @Environment(\.controlActiveState) private var controlActiveState
    let frame: ExposedFrame
    let size: CGSize
    let isSelected: Bool
    let isStripFocused: Bool
    let isInteractive: Bool
    let onSelect: () -> Void

    var body: some View {
        if isInteractive {
            face
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    model.openOutput(of: frame.id)
                }
                .simultaneousGesture(TapGesture().onEnded { onSelect() })
                .modifier(OutputDrag(url: frame.outputURL, image: frame.image, size: size))
                .contextMenu {
                    FrameContextMenu(frame: frame)
                }
                .help(helpText)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { rect in
                    FramePreviewController.shared.frameRects[frame.id] = rect
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { onSelect() }
                .accessibilityActions {
                    if frame.isUnsaved {
                        Button("Save…") { model.saveUnsaved(frame.id) }
                        Button("Open") { model.openOutput(of: frame.id) }
                    } else if frame.outputURL != nil {
                        Button("Open") { model.openOutput(of: frame.id) }
                        Button("Show in Finder") { model.reveal(frame.outputURL) }
                    } else {
                        Button("Retry") { model.retryJob(frame.id) }
                    }
                }
        } else {
            face
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var face: some View {
        ZStack {
            switch frame.development {
            case .developed:
                NegativeFrame(image: frame.image)
                if frame.isUnsaved {
                    UnsavedMark()
                }
            case .spoiled:
                FoggedFrame(image: frame.image, seed: FoggedFrame.seed(for: frame.id))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        // On a light table, the marked frame is the one lit from beneath.
        .brightness(isSelected ? 0.07 : 0)
        .overlay {
            if isSelected {
                GreasePencilMark(isEmphasized: isStripFocused && controlActiveState != .inactive)
                    .padding(-4)
            }
        }
    }

    private var helpText: String {
        switch frame.development {
        case .developed(let url) where frame.isUnsaved:
            "\(url.lastPathComponent) — not saved yet. Right-click to save it, or drag it out"
        case .developed(let url):
            "\(url.lastPathComponent) — double-click to open, or drag it out"
        case .spoiled(let message):
            "Couldn’t process \(frame.sourceURL.lastPathComponent): \(message)"
        }
    }

    private var accessibilityLabel: String {
        switch frame.development {
        case .developed(let url): frame.isUnsaved ? "\(url.lastPathComponent), not saved yet" : url.lastPathComponent
        case .spoiled: "\(frame.sourceURL.lastPathComponent), failed"
        }
    }
}

/// A frame developed but not yet saved: a dashed amber edge, like a print
/// waiting in the tray, and a small tray glyph in the corner.
private struct UnsavedMark: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(
                    FilmBackPalette.counter.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                )
            Image(systemName: "square.and.arrow.down.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(FilmBackPalette.counter)
                .shadow(color: .black.opacity(0.6), radius: 2)
                .padding(6)
        }
        .allowsHitTesting(false)
    }
}

/// The marked frame, ringed as with a china marker on a contact sheet: in
/// signal red while the strip has focus, faded when it doesn’t.
private struct GreasePencilMark: View {
    let isEmphasized: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(
                isEmphasized ? FilmBackPalette.signal : Color(hex: 0xB3B8BB, opacity: 0.6),
                style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: isEmphasized ? FilmBackPalette.signal.opacity(0.55) : .clear, radius: 5)
            .allowsHitTesting(false)
    }
}

/// The processed file as something to drag or copy. It is offered as the file
/// itself, so Finder and other apps take its real name instead of naming it
/// after its type, along with its image type for apps that want the picture.
enum OutputFile {
    static func itemProvider(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider(object: url as NSURL)
        provider.suggestedName = url.deletingPathExtension().lastPathComponent
        if let type = UTType(filenameExtension: url.pathExtension) {
            provider.registerFileRepresentation(for: type, visibility: .all, openInPlace: true) { completion in
                completion(url, true, nil)
                return nil
            }
        }
        return provider
    }
}

/// Drags the processed file out, lifting off the strip as a small print. It
/// runs its own drag session, so the strip knows when the frame is in the air
/// and the gate doesn’t light up for it.
private struct OutputDrag: ViewModifier {
    let url: URL?
    let image: CGImage?
    let size: CGSize
    @State private var source = FrameDragSource()

    func body(content: Content) -> some View {
        if let url {
            content.highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in
                        source.beginIfNeeded(url: url, image: image, size: size)
                    }
            )
        } else {
            content
        }
    }
}

@MainActor
private final class FrameDragSource: NSObject, NSDraggingSource {
    private var isDragging = false

    func beginIfNeeded(url: URL, image: CGImage?, size: CGSize) {
        guard !isDragging,
              let event = NSApp.currentEvent, event.type == .leftMouseDragged,
              let view = event.window?.contentView else { return }
        isDragging = true
        FilmRoll.shared.isDraggingFrame = true

        // The file itself goes on the pasteboard, so it lands under its own name.
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let print = Self.print(of: image, size: size)
        let location = view.convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(
                x: location.x - print.size.width / 2,
                y: location.y - print.size.height / 2,
                width: print.size.width,
                height: print.size.height
            ),
            contents: print
        )
        view.beginDraggingSession(with: [item], event: event, source: self)
    }

    /// The frame as a small print on cream paper.
    private static func print(of image: CGImage?, size: CGSize) -> NSImage {
        let border: CGFloat = 4
        let total = NSSize(width: size.width + border * 2, height: size.height + border * 2)
        return NSImage(size: total, flipped: false) { rect in
            NSColor(srgbRed: 0xF4 / 255, green: 0xEF / 255, blue: 0xE6 / 255, alpha: 1).setFill()
            rect.fill()
            let inner = rect.insetBy(dx: border, dy: border)
            NSColor(srgbRed: 0x2B / 255, green: 0x1C / 255, blue: 0x13 / 255, alpha: 1).setFill()
            inner.fill()
            guard let image, let context = NSGraphicsContext.current?.cgContext else { return true }
            // Scaled to fill, as the frame is on the strip.
            let scale = max(inner.width / CGFloat(image.width), inner.height / CGFloat(image.height))
            let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.saveGState()
            context.clip(to: inner)
            context.draw(image, in: CGRect(
                x: inner.midX - drawn.width / 2,
                y: inner.midY - drawn.height / 2,
                width: drawn.width,
                height: drawn.height
            ))
            context.restoreGState()
            return true
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        FilmRoll.shared.isDraggingFrame = false
    }
}

private struct FrameContextMenu: View {
    @Environment(AppModel.self) private var model
    let frame: ExposedFrame

    var body: some View {
        switch frame.development {
        case .developed(let url):
            if frame.isUnsaved {
                Button("Save…") {
                    model.saveUnsaved(frame.id)
                }
                Divider()
            }
            Button("Open") {
                model.openOutput(of: frame.id)
            }
            OpenWithMenu(url: url) { application in
                model.openOutput(of: frame.id, withApplicationAt: application)
            }
            if !frame.isUnsaved {
                Divider()
                Button("Show in Finder") {
                    model.reveal(url)
                }
            }
            Button("Copy") {
                model.copyOutput(of: frame.id)
            }
            ShareLink(item: url)
            Divider()
            Button("Open in Edit Mode") {
                model.openSourceInEditMode(of: frame.id)
            }
            Divider()
            Button(frame.isUnsaved ? "Discard" : "Move to Trash") {
                model.moveOutputToTrash(of: frame.id)
            }
        case .spoiled:
            Button("Retry") {
                model.retryJob(frame.id)
            }
            Divider()
            Button("Open in Edit Mode") {
                model.openSourceInEditMode(of: frame.id)
            }
            Button("Show Original in Finder") {
                model.revealSource(of: frame.id)
            }
        }
    }
}

/// The apps that can open a file, its default first, as in Finder.
private struct OpenWithMenu: View {
    let url: URL
    let open: (URL) -> Void

    var body: some View {
        Menu("Open With") {
            let workspace = NSWorkspace.shared
            let defaultApplication = workspace.urlForApplication(toOpen: url)
            let others = workspace.urlsForApplications(toOpen: url)
                .filter { $0 != defaultApplication }
                .sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
            if let defaultApplication {
                item(for: defaultApplication, title: "\(name(of: defaultApplication)) (default)")
                if !others.isEmpty {
                    Divider()
                }
            }
            ForEach(others, id: \.self) { application in
                item(for: application, title: name(of: application))
            }
        }
    }

    private func item(for application: URL, title: String) -> some View {
        Button {
            open(application)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(nsImage: icon(of: application))
            }
        }
    }

    private func name(of application: URL) -> String {
        let name = FileManager.default.displayName(atPath: application.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private func icon(of application: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: application.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

/// The fixed aperture the film runs under: the drop target and its prompt.
private struct FilmGate: View {
    let isEmpty: Bool
    let showsPrompt: Bool
    let isTargeted: Bool
    let onChoose: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(isTargeted ? Color(hex: 0x461406, opacity: 0.55) : Color(hex: 0x080402, opacity: 0.45))
                .opacity(isEmpty ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: isEmpty)
                .allowsHitTesting(false)

            if showsPrompt {
                prompt
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showsPrompt)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(isTargeted ? FilmBackPalette.signal : Color(hex: 0xB3B8BB), lineWidth: 2.5)
                .allowsHitTesting(false)
        )
        .shadow(color: isTargeted ? FilmBackPalette.signal.opacity(0.6) : .black.opacity(0.5), radius: isTargeted ? 14 : 3)
    }

    private var prompt: some View {
        VStack(spacing: 7) {
            Image(systemName: isTargeted ? "arrow.down.circle" : "photo.on.rectangle.angled")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(isTargeted ? FilmBackPalette.counter : Color(hex: 0xFFECDC, opacity: 0.85))
                .contentTransition(.symbolEffect(.replace))
            Text(isTargeted ? "Release to process" : "Drop images to process")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Button("Choose Images…", action: onChoose)
                .buttonStyle(GateButtonStyle())
        }
        .padding(8)
    }
}

/// A quiet, translucent button that sits on the film without competing with it.
private struct GateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GateButtonBody(configuration: configuration)
    }
}

private struct GateButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color(hex: 0xFFECDC, opacity: isHovering ? 0.95 : 0.8))
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(
                Capsule().fill(Color(hex: 0xFFECDC, opacity: configuration.isPressed ? 0.24 : isHovering ? 0.17 : 0.11))
            )
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

/// The shutter fires: a flash, the image passes through as a positive, then
/// settles into the film as a toned, mirrored negative.
private struct ExposureBurn: View {
    let image: CGImage?
    let isSpoiled: Bool
    let seed: UInt64
    let reduceMotion: Bool
    @State private var positive = 1.0
    @State private var flash = 1.0

    var body: some View {
        ZStack {
            Color(hex: 0x2B1C13)
            if let image {
                NegativeImage(image: image)
                Color.clear
                    .overlay {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .brightness(0.3 * positive)
                    .scaleEffect(x: -1, y: 1)
                    .opacity(positive)
            }
            if isSpoiled {
                FoggedFrame(image: image, seed: seed)
                    .transition(.opacity)
            }
            Color(hex: 0xFFFAF2).opacity(flash)
        }
        .animation(reduceMotion ? nil : .easeIn(duration: 0.5), value: isSpoiled)
        .onAppear {
            if reduceMotion {
                flash = 0
                positive = 0
                return
            }
            withAnimation(.easeOut(duration: 0.55)) { flash = 0 }
            if image != nil { burnIn() }
        }
        .onChange(of: image != nil) { _, hasImage in
            if hasImage, !reduceMotion { burnIn() }
        }
    }

    private func burnIn() {
        withAnimation(.easeInOut(duration: 1.1).delay(0.15)) { positive = 0 }
    }
}

// MARK: - Status bar

private struct FilmBackStatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            OutputFolderPopUp()

            Spacer(minLength: 20)

            // Progress shows on the film itself; only a failure needs words.
            if case .failed(let message) = model.jobs.first?.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(message)
            }

            // Frames developed under Ask Each Time and not yet saved.
            if !model.unsavedJobIDs.isEmpty {
                Button {
                    model.saveAllUnsaved()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save \(model.unsavedJobIDs.count)…")
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(FooterPopUpButtonStyle())
                .help("Choose where to save the processed images")
                .accessibilityLabel("Save \(model.unsavedJobIDs.count) unsaved \(model.unsavedJobIDs.count == 1 ? "image" : "images")")
            }

            // A lone image needs no count; a batch reads off “3 of 12”.
            if let batch = model.displayedBatch, batch.progress.total > 1 {
                BatchCounter(
                    progress: batch.progress,
                    canCancel: !batch.isWatched && model.canCancelProcessing,
                    onCancel: model.cancelInstantProcessing
                )
                .transition(.opacity)
            }

            HStack(spacing: 6) {
                Text("EXP")
                    .font(.system(size: 10, weight: .bold).width(.condensed))
                    .tracking(2.4)
                    .engraved()
                Text(String(format: "%02d", model.completedJobCount))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(FilmBackPalette.counter)
                    .shadow(color: FilmBackPalette.counter.opacity(0.55), radius: 4)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 38, minHeight: 22)
                    .background(CounterWindow())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: model.completedJobCount)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.completedJobCount) images processed")
        }
        .animation(.easeOut(duration: 0.2), value: (model.displayedBatch?.progress.total ?? 0) > 1)
        .font(.caption)
        .padding(.horizontal, 16)
        .frame(height: 42)
    }
}

/// “3 of 12” stamped beside the EXP counter while a batch runs, with a
/// recessed stop button that finishes the frame in the gate and goes no further.
private struct BatchCounter: View {
    let progress: ProcessingBatch
    let canCancel: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text(progress.isCancelled ? "Stopping…" : "\(progress.position) of \(progress.total)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.snappy, value: progress.position)
                .engraved()
                .accessibilityLabel(
                    progress.isCancelled
                        ? "Stopping after this image"
                        : "Processing image \(progress.position) of \(progress.total)"
                )

            if canCancel {
                Button(action: onCancel) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 7, weight: .bold))
                }
                .buttonStyle(RecessedButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Cancel processing after this image")
                .accessibilityLabel("Cancel Processing")
            }
        }
    }
}

/// A small round button sunk into the metal, its glyph lit like the counter.
private struct RecessedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RecessedButtonBody(configuration: configuration)
    }
}

private struct RecessedButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(FilmBackPalette.counter.opacity(isHovering || configuration.isPressed ? 1 : 0.8))
            .shadow(color: FilmBackPalette.counter.opacity(isHovering ? 0.7 : 0.4), radius: 3)
            .frame(width: 18, height: 18)
            .background(
                Circle()
                    .fill(Color(hex: configuration.isPressed ? 0x050505 : 0x0D0D0D))
                    .shadow(color: .white.opacity(0.7), radius: 0, y: 1)
            )
            .contentShape(Circle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

/// The Instant output folder as a path pop-up stamped into the footer. Its
/// menu lists recent folders, then Choose… and Show in Finder.
private struct OutputFolderPopUp: View {
    @Environment(AppModel.self) private var model
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            OutputFolderMenu.popUp(model: model, from: anchor.view)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.asksWhereToSaveInstantly ? OutputFolderMenu.askSymbol : "folder")
                Text(model.dropOutputTitle)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .opacity(0.8)
            }
        }
        .buttonStyle(FooterPopUpButtonStyle())
        .background(MenuAnchorView(anchor: anchor))
        .help(outputHelp)
        .accessibilityLabel("Output Folder")
        .accessibilityValue(model.asksWhereToSaveInstantly ? "Ask Each Time" : model.dropOutputFolder?.lastPathComponent ?? "None")
        .accessibilityHint("Shows recent folders and lets you choose another")
    }
}

private extension OutputFolderPopUp {
    var outputHelp: String {
        if model.asksWhereToSaveInstantly {
            return "Asking where to save after the images are processed"
        }
        return model.dropOutputFolder.map { "Saving to \($0.path(percentEncoded: false))" }
            ?? "Choose where processed images are saved"
    }
}

/// Stamped lettering that sinks slightly into the metal under the pointer.
private struct FooterPopUpButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FooterPopUpBody(configuration: configuration)
    }
}

private struct FooterPopUpBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let shade: Color = colorScheme == .dark ? .black : Color(hex: 0x3F4347)
        configuration.label
            .engraved()
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(shade.opacity(configuration.isPressed ? 0.18 : isHovering ? 0.09 : 0))
                    .shadow(color: .white.opacity(isHovering && colorScheme == .light ? 0.6 : 0), radius: 0, y: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
