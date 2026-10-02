import GranularCore
import SwiftUI

// The film back stood upright for the phone: the canister lies on its side at
// the foot of the chamber and the film runs up out of its lip, through the
// gate, and curls away into the take-up at the top.
//
// The strip is laid out lengthwise, exactly as on the Mac, and turned a
// quarter to run upward. Everything printed on the film turns with it; the
// pictures in the frames are turned back so they stand upright.

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
    let development: Development
    /// Developed, but not in the library yet.
    var isUnsaved = false

    var outputURL: URL? {
        if case .developed(let url) = development { return url }
        return nil
    }
}

struct FilmChamber<Canister: View>: View {
    let style: CanisterStyle
    let recipeName: String
    let gate: GateExposure?
    let frames: [ExposedFrame]
    let advance: CGFloat
    let isAdvancing: Bool
    let framesWound: Int
    let isCanisterSeated: Bool
    let filmOut: CGFloat
    let reduceMotion: Bool
    let onChoose: () -> Void
    let onOpen: (ExposedFrame) -> Void
    let onRetry: (UUID) -> Void
    /// The tin, wrapped in whatever opens the recipe menu.
    @ViewBuilder let canister: (_ tin: AnyView) -> Canister

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let g = CanisterGeometry.self
            // Lying down, the tin's 320 pt design height runs across the chamber
            // and its width becomes its height on screen.
            let stripMid = g.topCap + g.bodyHeight / 2
            let scale = min(0.95, (width / 2 - 14) / (g.height - stripMid))
            let canisterLength = g.height * scale
            let canisterThickness = g.width * scale
            let canisterTop = height - canisterThickness - 22
            // Centred on the film, not on the tin.
            let canisterLeading = width / 2 - (g.height - stripMid) * scale
            let stripThickness = (g.bodyHeight * scale * g.filmToBody).rounded()
            let stripLeading = canisterLeading + (g.height - g.topCap - g.bodyHeight + (g.bodyHeight * scale - stripThickness) / scale * 0.75) * scale
            // The film comes out from under the lip, which lies along the top of the tin.
            let stripLength = canisterTop + (2 + g.lipWidth / 2) * scale
            let curl = FilmStrip.curlWidth(for: stripLength)
            let metrics = StripMetrics(format: style.format, height: stripThickness)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: 0x0A0A0A))
                    .overlay(sunkEdge(cornerRadius: 14))
                    .frame(width: canisterLength + 18, height: canisterThickness + 30)
                    .offset(x: canisterLeading - 9, y: canisterTop - 12)

                takeUpSlot(leading: stripLeading - 9, width: stripThickness + 18, depth: curl + 14)

                rail(x: stripLeading - 9, from: curl + 18, to: stripLength - 30)
                rail(x: stripLeading + stripThickness + 5, from: curl + 18, to: stripLength - 30)

                FilmStrip(
                    format: style.format,
                    recipeName: recipeName,
                    gate: gate,
                    frames: frames,
                    advance: advance,
                    isAdvancing: isAdvancing,
                    framesWound: framesWound,
                    reduceMotion: reduceMotion,
                    onChoose: onChoose,
                    onOpen: onOpen,
                    onRetry: onRetry
                )
                .frame(width: stripLength, height: stripThickness)
                // Loading: the film slides out of the canister's lip toward the take-up.
                .offset(x: -(1 - filmOut) * 60)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: stripLength * filmOut)
                }
                .allowsHitTesting(filmOut == 1)
                .rotationEffect(.degrees(-90))
                .frame(width: stripThickness, height: stripLength)
                .offset(x: stripLeading)

                if let gate, !reduceMotion {
                    ChamberFlash(center: UnitPoint(
                        x: (stripLeading + stripThickness / 2) / width,
                        y: (stripLength - metrics.leader - metrics.frameWidth / 2) / height
                    ))
                    .id(gate.id)
                    .allowsHitTesting(false)
                }

                canister(AnyView(
                    FilmCanisterView(style: style, recipeName: recipeName, height: canisterLength, lipLeading: true, castsShadow: false)
                        .frame(width: canisterThickness, height: canisterLength)
                        .rotationEffect(.degrees(90))
                        .frame(width: canisterLength, height: canisterThickness)
                        .shadow(color: .black.opacity(0.6), radius: 12 * scale, y: 10 * scale)
                ))
                .offset(y: isCanisterSeated ? 0 : canisterThickness * 0.4)
                .scaleEffect(isCanisterSeated ? 1 : 1.04)
                .opacity(isCanisterSeated ? 1 : 0)
                .id(style)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
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
                center: UnitPoint(x: 0.5, y: 0.5),
                startRadius: 0,
                endRadius: 520
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            sunkEdge(cornerRadius: 12, width: 10, blur: 7, opacity: 0.9)
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.black.opacity(0.55), .white.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
    }

    /// The shadowed inner edge of anything sunk into the body.
    private func sunkEdge(cornerRadius: CGFloat, width: CGFloat = 8, blur: CGFloat = 6, opacity: Double = 1) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(.black.opacity(opacity), lineWidth: width)
            .blur(radius: blur)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // The sunk edge never changes while the film moves; draw it once.
            .drawingGroup()
    }

    /// The opening the film curls into on its way to the take-up spool, running
    /// off the top of the chamber.
    private func takeUpSlot(leading: CGFloat, width: CGFloat, depth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(hex: 0x0A0A0A))
            .overlay(sunkEdge(cornerRadius: 10))
            .frame(width: width, height: depth + 20)
            .offset(x: leading, y: -20)
    }

    private func rail(x: CGFloat, from start: CGFloat, to end: CGFloat) -> some View {
        Capsule()
            .fill(LinearGradient(colors: [Color(hex: 0xECEEF0), Color(hex: 0x8D9296), Color(hex: 0x5A5E62)], startPoint: .leading, endPoint: .trailing))
            .frame(width: 4, height: max(0, end - start))
            .shadow(color: .black.opacity(0.7), radius: 2, x: 2)
            .offset(x: x, y: start)
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

// MARK: - Film strip

struct StripMetrics {
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

/// Turns a picture laid out for the upright phone into the film's sideways
/// frame, so it stands upright again once the strip is turned.
private extension View {
    func upright(in slot: CGSize) -> some View {
        frame(width: slot.height, height: slot.width)
            .rotationEffect(.degrees(90))
            .frame(width: slot.width, height: slot.height)
    }
}

/// The back of the film: dark base, perforations and edge print, running under
/// a fixed gate. Exposed frames ride the film as it winds on, and the far end
/// curls away toward the implied take-up spool.
private struct FilmStrip: View {
    let format: FilmFormat
    let recipeName: String
    let gate: GateExposure?
    let frames: [ExposedFrame]
    let advance: CGFloat
    let isAdvancing: Bool
    let framesWound: Int
    let reduceMotion: Bool
    let onChoose: () -> Void
    let onOpen: (ExposedFrame) -> Void
    let onRetry: (UUID) -> Void

    private let curlAngles: [Double] = stride(from: 4.0, through: 88, by: 4).map { $0 }

    /// How much of the strip's far end bends away behind the chamber wall.
    static func curlWidth(for length: CGFloat) -> CGFloat {
        min(30, length * 0.07)
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
                        // film turns away behind rather than drooping.
                        .scaleEffect(x: cosines[index], y: 1 - pow(bend, 0.75) * pinch, anchor: .leading)
                        .offset(x: displayX)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                // One continuous falloff across the curl so the segments read as a bend.
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0),
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
                    slot: CGSize(width: metrics.frameWidth, height: metrics.frameHeight),
                    showsPrompt: gate == nil && !isAdvancing,
                    onChoose: onChoose
                )
                .offset(x: metrics.leader, y: metrics.bandTop)
            }
        }
    }

    /// The film itself, laid out one frame early and shifted by `advance`, so
    /// winding on is a single move of everything printed on it.
    ///
    /// The curl repeats the film once per slice, each showing a sliver of it.
    /// `slice` is that sliver’s span along the film; what lies outside it is
    /// never seen, so it isn’t drawn.
    private func film(width: CGFloat, height: CGFloat, metrics: StripMetrics, slice: ClosedRange<CGFloat>?) -> some View {
        let isPrimary = slice == nil
        let pitch = metrics.pitch
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
                            .upright(in: slot)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .accessibilityLabel("Exposing image")
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: slot.width, height: slot.height)

                    ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                        let start = metrics.leader + CGFloat(index) * pitch
                        if let slice, start - 16 > slice.upperBound || start + pitch + slot.width + 16 < slice.lowerBound {
                            Color.clear.frame(width: slot.width, height: slot.height)
                        } else {
                            StripFrame(
                                frame: frame,
                                slot: slot,
                                // The curl only repeats the film to look at.
                                isInteractive: isPrimary,
                                onOpen: { onOpen(frame) },
                                onRetry: { onRetry(frame.id) }
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
                    // The film name marks the unexposed frame in the gate.
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
/// an amber fog washing in from the edge.
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

/// A frame on the strip. Tapping opens the developed picture; holding it
/// brings up the rest.
private struct StripFrame: View {
    let frame: ExposedFrame
    let slot: CGSize
    let isInteractive: Bool
    let onOpen: () -> Void
    let onRetry: () -> Void

    var body: some View {
        if isInteractive {
            face
                .contentShape(Rectangle())
                .onTapGesture {
                    if frame.outputURL != nil { onOpen() } else { onRetry() }
                }
                .contextMenu {
                    menu
                } preview: {
                    preview
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { frame.outputURL != nil ? onOpen() : onRetry() }
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
        .upright(in: slot)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    @ViewBuilder
    private var menu: some View {
        switch frame.development {
        case .developed(let url):
            Button("View", systemImage: "eye", action: onOpen)
            ShareLink(item: url)
        case .spoiled(let message):
            Text(message)
            Button("Retry", systemImage: "arrow.clockwise", action: onRetry)
        }
    }

    /// The print, the right way up and the right way round.
    @ViewBuilder
    private var preview: some View {
        if let image = frame.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 360, maxHeight: 480)
        }
    }

    private var accessibilityLabel: String {
        switch frame.development {
        case .developed: frame.isUnsaved ? "Developed frame, not saved to Photos" : "Developed frame"
        case .spoiled(let message): "Failed frame: \(message)"
        }
    }
}

/// A frame developed but not yet in the library: a dashed amber edge, like a
/// print waiting in the tray.
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

/// The fixed aperture the film runs under, and the way to load it.
private struct FilmGate: View {
    let slot: CGSize
    let showsPrompt: Bool
    let onChoose: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: 0x080402, opacity: 0.45))
                .opacity(showsPrompt ? 1 : 0)
                .allowsHitTesting(false)

            if showsPrompt {
                Button(action: onChoose) {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(Color(hex: 0xFFECDC, opacity: 0.85))
                        Text("Choose Photos")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: 0xFFECDC, opacity: 0.9))
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(Capsule().fill(Color(hex: 0xFFECDC, opacity: 0.12)))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(GateButtonStyle())
                .upright(in: slot)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showsPrompt)
        .frame(width: slot.width, height: slot.height)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color(hex: 0xB3B8BB), lineWidth: 2.5)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.5), radius: 3)
    }
}

private struct GateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
