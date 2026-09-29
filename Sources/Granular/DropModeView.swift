import GranularCore
import ImageIO
import SwiftUI

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
    private var roll: FilmRoll { .shared }

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
                gate: exposure.map { GateExposure(id: $0.jobID, image: roll.thumbnails[$0.jobID]?.image) },
                frames: exposedFrames,
                advance: advance,
                isAdvancing: isAdvancing,
                framesWound: roll.framesWound,
                isCanisterSeated: isCanisterSeated,
                filmOut: filmOut,
                isTargeted: model.isDropTargeted,
                reduceMotion: reduceMotion,
                onCanister: { RecipeMenuPresenter.popUp(model: model) },
                onChoose: { model.chooseImagesForDroplet() }
            )
            .padding(.horizontal, 10)
            .padding(.top, 2)

            FilmBackStatusBar()
        }
        .background(AlloySurface().ignoresSafeArea())
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.processInstantly(urls) }
            return !urls.isEmpty
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.16)) {
                model.isDropTargeted = targeted
            }
        }
        .onChange(of: LeadJobKey(id: model.jobs.first?.id, state: model.jobs.first?.state)) { _, _ in
            leadJobChanged()
        }
        .onAppear {
            if model.isFilmLoaded {
                isCanisterSeated = true
                filmOut = 1
            }
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
            guard case .finished = job.state, job.id != exposure?.jobID else { return nil }
            return ExposedFrame(id: job.id, image: roll.thumbnails[job.id]?.image)
        }
        .prefix(4)
        .map { $0 }
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
            if exposure?.jobID == job.id {
                withAnimation(.easeOut(duration: 0.3)) { exposure = nil }
            }
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
            }
        }
    }

    private func loadThumbnail(from url: URL, for jobID: UUID) {
        Task {
            guard let thumbnail = await FilmThumbnail.load(url) else { return }
            let visible = Set(model.jobs.prefix(6).map(\.id))
            roll.thumbnails[jobID] = thumbnail
            roll.thumbnails = roll.thumbnails.filter { visible.contains($0.key) }
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
}

struct ExposedFrame: Identifiable, Equatable {
    let id: UUID
    let image: CGImage?
}

// MARK: - Chamber

private struct FilmChamber: View {
    let style: CanisterStyle
    let recipeName: String
    let gate: GateExposure?
    let frames: [ExposedFrame]
    let advance: CGFloat
    let isAdvancing: Bool
    let framesWound: Int
    let isCanisterSeated: Bool
    let filmOut: CGFloat
    let isTargeted: Bool
    let reduceMotion: Bool
    let onCanister: () -> Void
    let onChoose: () -> Void

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
                    )
                    .frame(width: bodyTrailing + 4, height: canisterHeight + 18)
                    .offset(x: 8, y: canisterTop - 9)

                rail(y: stripTop - 9, from: stripLeading + 30, to: width - 70)
                rail(y: stripTop + stripHeight + 5, from: stripLeading + 30, to: width - 70)

                FilmStrip(
                    format: format,
                    recipeName: recipeName,
                    gate: gate,
                    frames: frames,
                    advance: advance,
                    isAdvancing: isAdvancing,
                    framesWound: framesWound,
                    isTargeted: isTargeted,
                    reduceMotion: reduceMotion,
                    onChoose: onChoose
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
        bandBottom = (height * format.bandBottom).rounded()
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
    let advance: CGFloat
    let isAdvancing: Bool
    let framesWound: Int
    let isTargeted: Bool
    let reduceMotion: Bool
    let onChoose: () -> Void

    private let curlAngles: [Double] = stride(from: 6.0, through: 84, by: 6).map { $0 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let metrics = StripMetrics(format: format, height: height)
            let curlWidth = min(96, width * 0.2)
            let flatWidth = width - curlWidth
            let cosines = curlAngles.map { cos($0 * .pi / 180) }
            let segment = curlWidth / cosines.reduce(0, +)
            let contentWidth = flatWidth + segment * CGFloat(curlAngles.count)

            ZStack(alignment: .topLeading) {
                film(width: contentWidth, height: height, metrics: metrics, isPrimary: true)
                    .frame(width: flatWidth, height: height, alignment: .leading)
                    .clipped()

                ForEach(curlAngles.indices, id: \.self) { index in
                    let start = flatWidth + segment * CGFloat(index)
                    let displayX = flatWidth + segment * cosines[..<index].reduce(0, +)
                    let bend = 1 - cosines[index]
                    film(width: contentWidth, height: height, metrics: metrics, isPrimary: false)
                        .offset(x: -start)
                        .frame(width: segment, height: height, alignment: .leading)
                        .clipped()
                        .scaleEffect(x: cosines[index], y: 1 - 0.08 * bend, anchor: .leading)
                        .offset(x: displayX, y: 10 * bend)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                // One continuous falloff across the curl so the segments read as a bend.
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.06), location: 0.12),
                        .init(color: .black.opacity(0.25), location: 0.35),
                        .init(color: .black.opacity(0.7), location: 0.75),
                        .init(color: .black.opacity(0.95), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: curlWidth + 2, height: height + 12)
                .offset(x: flatWidth - 1)
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
    private func film(width: CGFloat, height: CGFloat, metrics: StripMetrics, isPrimary: Bool) -> some View {
        let pitch = metrics.pitch
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
                    firstFrame: 0
                )
                HStack(spacing: metrics.gap) {
                    // The frame that has just left the canister side of the gate.
                    Color.clear.frame(width: slot.width, height: slot.height)

                    Group {
                        if let gate, isPrimary {
                            ExposureBurn(image: gate.image, reduceMotion: reduceMotion)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .accessibilityLabel("Exposing image")
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: slot.width, height: slot.height)

                    ForEach(frames) { frame in
                        NegativeFrame(image: frame.image)
                            .frame(width: slot.width, height: slot.height)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .accessibilityLabel("Processed image")
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
                    firstFrame: framesWound + 2
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
    let width: CGFloat
    let height: CGFloat
    let perforated: Bool
    let perforationsPerFrame: Int
    let pitch: CGFloat
    let leader: CGFloat
    let edgePrint: String?
    /// Frame number printed at the first slot, counting down slot by slot.
    let firstFrame: Int

    var body: some View {
        Canvas { context, size in
            let printHeight: CGFloat = edgePrint == nil ? 0 : 10
            if perforated, perforationsPerFrame > 0 {
                let perfPitch = pitch / CGFloat(perforationsPerFrame)
                let holeWidth = min(perfPitch * 0.42, 14)
                let holeHeight = min(size.height - printHeight - 6, holeWidth * 1.65)
                let y = printHeight + (size.height - printHeight - holeHeight) / 2
                var x: CGFloat = leader * 0.5
                while x < size.width {
                    let hole = Path(roundedRect: CGRect(x: x, y: y, width: holeWidth, height: holeHeight), cornerRadius: 2)
                    context.fill(hole, with: .color(Color(hex: 0x050404)))
                    context.stroke(hole, with: .color(Color(hex: 0xFFD2AA, opacity: 0.1)), lineWidth: 0.75)
                    x += perfPitch
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
                    let marker = number % 3 == 1 ? "\(edgePrint)   ▸ \(number)" : "▸ \(number)    ▸ \(number)A"
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
            Color(hex: 0xFFFAF2).opacity(flash)
        }
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
            HStack(spacing: 7) {
                Image(systemName: "folder")
                Text(model.dropOutputFolder?.lastPathComponent ?? "Choose output folder")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Button("Change…") {
                    model.chooseDropOutputFolder()
                }
                .buttonStyle(.link)
            }
            .engraved()

            Spacer(minLength: 20)

            if let last = model.jobs.first {
                CompactJobStatus(job: last)
            } else {
                Text(model.statusMessage)
                    .engraved()
                    .lineLimit(1)
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
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(hex: 0x0D0D0D))
                            .shadow(color: .white.opacity(0.7), radius: 0, y: 1)
                    )
                    .contentTransition(.numericText())
                    .animation(.snappy, value: model.completedJobCount)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.completedJobCount) images processed")
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .frame(height: 42)
    }
}

struct CompactJobStatus: View {
    @Environment(AppModel.self) private var model
    let job: ProcessingJob

    var body: some View {
        HStack(spacing: 6) {
            switch job.state {
            case .queued:
                Image(systemName: "clock")
            case .processing:
                ProgressView().controlSize(.small)
            case .finished:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text(job.sourceURL.lastPathComponent)
                .lineLimit(1)
            switch job.state {
            case .finished(let outputURL):
                Button {
                    model.reveal(outputURL)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Show in Finder")
                .help("Show in Finder")
            default:
                Text(job.state.label)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
