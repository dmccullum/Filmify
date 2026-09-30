import AppKit
import GranularCore
import Observation
import SwiftUI

@MainActor
@Observable
final class ViewerZoomController {
    /// Zoom in device pixels: 1 is 100%, one image pixel per screen pixel.
    private(set) var scale = 1.0
    private(set) var fitScale = 1.0
    private(set) var isFitted = true
    /// How far the image is dragged from the centre of the viewport, in points.
    private(set) var panOffset = CGSize.zero
    private(set) var viewportSize = CGSize.zero
    /// Whether jumps (Fit, 100%, presets, double-click) glide instead of cutting.
    var animatesJumps = true
    private var imagePixelSize = CGSize.zero
    private var backingScale = 2.0

    /// The image's size on screen, in points.
    var displaySize: CGSize {
        CGSize(
            width: imagePixelSize.width * scale / backingScale,
            height: imagePixelSize.height * scale / backingScale
        )
    }

    var canPan: Bool {
        displaySize.width > viewportSize.width || displaySize.height > viewportSize.height
    }

    func updateGeometry(viewport: CGSize, imagePixelSize: CGSize, backingScale: Double) {
        viewportSize = viewport
        self.imagePixelSize = imagePixelSize
        self.backingScale = max(1, backingScale)
        fitScale = ViewerZoomMath.clampedScale(
            ViewerZoomMath.fitScale(
                imageWidth: Double(imagePixelSize.width),
                imageHeight: Double(imagePixelSize.height),
                viewportWidth: Double(viewport.width),
                viewportHeight: Double(viewport.height)
            ) * self.backingScale
        )
        if isFitted {
            scale = fitScale
            panOffset = .zero
        } else {
            panOffset = clamped(panOffset)
        }
    }

    // The zoom commands act on the centre of the viewport unless given the
    // point under the cursor to keep still.

    func zoomIn(around anchor: CGPoint = .zero) {
        jump { setManualScale(ViewerZoomMath.zoomedIn(from: scale), around: anchor) }
    }

    func zoomOut(around anchor: CGPoint = .zero) {
        jump { setManualScale(ViewerZoomMath.zoomedOut(from: scale), around: anchor) }
    }

    func actualSize(around anchor: CGPoint = .zero) {
        jumpToScale(ViewerZoomMath.actualSizeScale, around: anchor)
    }

    func jumpToScale(_ scale: Double, around anchor: CGPoint = .zero) {
        jump { setManualScale(scale, around: anchor) }
    }

    /// Double-click and the trackpad’s smart zoom: Fit, or 100% where you clicked.
    func toggleFitAndActualSize(around anchor: CGPoint) {
        if ViewerZoomMath.isActualSize(scale) {
            fit()
        } else {
            actualSize(around: anchor)
        }
    }

    func fit() {
        jump {
            isFitted = true
            scale = fitScale
            panOffset = .zero
        }
    }

    func setManualScale(_ newScale: Double, around anchor: CGPoint = .zero) {
        let oldScale = scale
        let newScale = ViewerZoomMath.clampedScale(newScale)
        isFitted = false
        scale = newScale
        panOffset = clamped(CGSize(
            width: ViewerZoomMath.anchoredPanOffset(
                Double(panOffset.width), anchor: Double(anchor.x), oldScale: oldScale, newScale: newScale
            ),
            height: ViewerZoomMath.anchoredPanOffset(
                Double(panOffset.height), anchor: Double(anchor.y), oldScale: oldScale, newScale: newScale
            )
        ))
    }

    func zoom(by factor: Double, around anchor: CGPoint) {
        setManualScale(scale * factor, around: anchor)
    }

    func setPanOffset(_ offset: CGSize) {
        panOffset = clamped(offset)
    }

    func pan(by delta: CGSize) {
        setPanOffset(CGSize(width: panOffset.width + delta.width, height: panOffset.height + delta.height))
    }

    func resetForNewImage() {
        fit()
    }

    private func jump(_ change: () -> Void) {
        if animatesJumps {
            withAnimation(.smooth(duration: 0.22), change)
        } else {
            change()
        }
    }

    private func clamped(_ offset: CGSize) -> CGSize {
        let display = displaySize
        return CGSize(
            width: CGFloat(ViewerZoomMath.clampedPanOffset(
                Double(offset.width),
                displayLength: Double(display.width),
                viewportLength: Double(viewportSize.width)
            )),
            height: CGFloat(ViewerZoomMath.clampedPanOffset(
                Double(offset.height),
                displayLength: Double(display.height),
                viewportLength: Double(viewportSize.height)
            ))
        )
    }
}

private struct GranularViewerZoomControllerKey: FocusedValueKey {
    typealias Value = ViewerZoomController
}

extension FocusedValues {
    var granularViewerZoomController: ViewerZoomController? {
        get { self[GranularViewerZoomControllerKey.self] }
        set { self[GranularViewerZoomControllerKey.self] = newValue }
    }
}

// Edit mode is split into small views that each read only the model state
// they show, so a slider drag, which changes the recipe and then the preview
// many times a second, updates the canvas image and the controls being
// dragged rather than the whole window.

struct EditModeView: View {
    @Environment(AppModel.self) private var model
    @State private var zoomController = ViewerZoomController()
    @FocusState private var isCanvasFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                EditorCanvas(zoomController: zoomController)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    // Focusable so ⌘C copies the image once the canvas is clicked,
                    // leaving Copy to the text fields whenever one of those has focus.
                    .focusable(interactions: .edit)
                    .focused($isCanvasFocused)
                    .focusEffectDisabled()
                    .onCopyCommand {
                        model.copyProcessedImage()
                        return []
                    }
                    // Edit mode shows one image at a time: a drop of several
                    // opens the first and offers the rest to Instant mode.
                    .dropDestination(for: URL.self) { urls, _ in
                        model.openForEditing(urls)
                        return !urls.isEmpty
                    }
            }

            AdjustmentsInspector()
                .environment(model)
                .frame(width: 310)
                .background(.bar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background { CenterAdjustmentDismissal() }
        .focusedSceneValue(\.granularViewerZoomController, zoomController)
        .onChange(of: model.selectedSourceURL) { _, _ in
            zoomController.resetForNewImage()
            model.finishCenterAdjustment()
        }
        .onChange(of: model.selectedSourceURL, initial: true) { previous, url in
            // A newly opened image takes focus, so ⌘C copies it straight away.
            // (On first appearance, `previous` is the current image.)
            if url != nil, previous == nil || previous == url {
                isCanvasFocused = true
            }
        }
        .onExitCommand(perform: model.finishCenterAdjustment)
        .onDisappear(perform: model.finishCenterAdjustment)
    }
}

/// The image and what floats over it, or the empty state.
private struct EditorCanvas: View {
    @Environment(AppModel.self) private var model
    let zoomController: ViewerZoomController

    var body: some View {
        ZStack {
            if let image = model.previewImage {
                ZoomableImageCanvas(
                    image: image,
                    imagePixelSize: model.sourceInfo?.pixelSize ?? image.pixelDimensions,
                    zoomController: zoomController
                )
                .id(model.selectedSourceURL)

                CanvasOverlays(zoomController: zoomController)
            } else {
                EditorEmptyState()
            }

            FirstPreviewProgress()
        }
    }
}

private struct CanvasOverlays: View {
    @Environment(AppModel.self) private var model
    let zoomController: ViewerZoomController

    var body: some View {
        VStack {
            ZStack {
                if let target = model.activeCenterTarget {
                    CenterAdjustmentStatusBar(target: target)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack {
                    Spacer()
                    if model.activeCenterTarget == nil, model.processedPreview != nil {
                        CompareButton()
                        EditorShareButton()
                    }
                }
            }
            Spacer()
            EditorActivity()
            ZoomControls(zoomController: zoomController)
        }
        .padding(16)
    }
}

/// Edits render live; only the first render of a newly opened photo is slow
/// enough to show.
private struct FirstPreviewProgress: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isRenderingPreview, model.processedPreview == nil, model.selectedSourceURL != nil {
            ProgressView()
                .controlSize(.small)
                .padding(9)
                .background(.regularMaterial, in: Circle())
        }
    }
}

/// Puts the centre target away when its effect is switched off. It watches
/// the recipe from a view of its own, so the rest of Edit mode doesn’t update
/// with every change to it.
private struct CenterAdjustmentDismissal: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Color.clear
            .onChange(of: model.recipe.lightShaping.isEnabled) { _, enabled in
                dismiss(.vignette, when: enabled)
            }
            .onChange(of: model.recipe.lensBlur.isEnabled) { _, enabled in
                dismiss(.lensBlur, when: enabled)
            }
            .accessibilityHidden(true)
    }

    private func dismiss(_ target: EffectCenterTarget, when enabled: Bool) {
        if !enabled, model.activeCenterTarget == target {
            model.finishCenterAdjustment()
        }
    }
}

/// Before/After: hold to peek at the original, click to switch and stay.
/// (Space held over the canvas peeks the same way.)
private struct CompareButton: View {
    @Environment(AppModel.self) private var model
    @State private var pressStart: Date?
    @State private var lastPointerEnd = Date.distantPast

    /// A press shorter than this is a click; longer is a hold to peek.
    private static let clickDuration = 0.3

    var body: some View {
        Button(action: activateWithoutPointer) {
            Label(
                model.isShowingOriginal ? "Before" : "After",
                systemImage: model.isShowingOriginal ? "eye.slash" : "eye"
            )
        }
        .buttonStyle(.glass)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard pressStart == nil else { return }
                    pressStart = .now
                    model.isHoldingCompare = true
                }
                .onEnded { _ in
                    let held = Date.now.timeIntervalSince(pressStart ?? .now)
                    pressStart = nil
                    lastPointerEnd = .now
                    model.isHoldingCompare = false
                    if held < Self.clickDuration {
                        model.showOriginal.toggle()
                    }
                }
        )
        .onDisappear {
            model.isHoldingCompare = false
        }
        .help(
            "Hold to see the original. Click to switch between Before and After. " +
            "You can also hold Space, or press \\ to switch."
        )
        .accessibilityLabel("Compare Before and After")
        .accessibilityValue(model.isShowingOriginal ? "Before" : "After")
    }

    /// Keyboard and VoiceOver activations, which arrive without a press. A
    /// click is decided by the gesture above, so a pointer's own action is ignored.
    private func activateWithoutPointer() {
        guard pressStart == nil, Date.now.timeIntervalSince(lastPointerEnd) > Self.clickDuration else { return }
        model.showOriginal.toggle()
    }
}

private struct ZoomableImageCanvas: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let image: NSImage
    let imagePixelSize: CGSize
    let zoomController: ViewerZoomController
    @State private var dragStartOffset: CGSize?

    private struct Geometry: Equatable {
        var viewport: CGSize
        var imagePixelSize: CGSize
        var backingScale: Double
    }

    var body: some View {
        GeometryReader { proxy in
            let displaySize = zoomController.displaySize
            let canPan = zoomController.canPan

            ZStack {
                Color.clear
                ZStack {
                    ViewerImage(image: image, size: displaySize, castsShadow: !canPan)
                        .contentShape(Rectangle())
                        .gesture(panGesture(canPan: canPan))
                        .processedImageDragSource(isEnabled: !canPan && model.activeCenterTarget == nil)

                    if let target = model.activeCenterTarget {
                        ImageCenterOverlay(
                            target: target,
                            position: model.centerPosition(for: target)
                        ) { x, y in
                            model.updateCenter(for: target, x: x, y: y)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: displaySize.width, height: displaySize.height)
                .offset(zoomController.panOffset)
                .animation(.smooth(duration: 0.18), value: model.activeCenterTarget)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active:
                            if model.activeCenterTarget != nil {
                                NSCursor.crosshair.set()
                            } else {
                                (canPan ? NSCursor.openHand : NSCursor.arrow).set()
                            }
                        case .ended:
                            NSCursor.arrow.set()
                        }
                    }
            }
            .clipped()
            .contentShape(Rectangle())
            .background {
                ViewerInputMonitor(model: model, zoomController: zoomController)
            }
            .simultaneousGesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        // The centre target owns clicks while it is being placed.
                        guard model.activeCenterTarget == nil else { return }
                        zoomController.toggleFitAndActualSize(around: CGPoint(
                            x: value.location.x - proxy.size.width / 2,
                            y: value.location.y - proxy.size.height / 2
                        ))
                    }
            )
            .onChange(
                of: Geometry(viewport: proxy.size, imagePixelSize: imagePixelSize, backingScale: displayScale),
                initial: true
            ) { _, geometry in
                zoomController.updateGeometry(
                    viewport: geometry.viewport,
                    imagePixelSize: geometry.imagePixelSize,
                    backingScale: geometry.backingScale
                )
            }
            .onChange(of: reduceMotion, initial: true) { _, reduceMotion in
                zoomController.animatesJumps = !reduceMotion
            }
            // Only the zoom decides how sharp a preview is needed; panning doesn’t.
            .onChange(
                of: zoomController.scale * max(imagePixelSize.width, imagePixelSize.height),
                initial: true
            ) { _, longEdge in
                model.setPreviewDisplaySize(longEdge: longEdge)
            }
            .onDisappear {
                NSCursor.arrow.set()
            }
        }
    }

    private func panGesture(canPan: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard canPan, model.activeCenterTarget == nil else { return }
                if dragStartOffset == nil {
                    dragStartOffset = zoomController.panOffset
                }
                let start = dragStartOffset ?? .zero
                zoomController.setPanOffset(CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                ))
                NSCursor.closedHand.set()
            }
            .onEnded { _ in
                dragStartOffset = nil
                if model.activeCenterTarget != nil {
                    NSCursor.crosshair.set()
                } else {
                    (canPan ? NSCursor.openHand : NSCursor.arrow).set()
                }
            }
    }
}

/// The image at its size on screen. Its inputs don’t change as the image is
/// panned, so panning moves it without drawing it again.
private struct ViewerImage: View {
    let image: NSImage
    let size: CGSize
    let castsShadow: Bool

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            // The shadow is cast by a plain shape behind the image, so it
            // doesn’t trace the image’s pixels as it zooms; once the image
            // fills the viewer, no edge shows to cast one.
            .background {
                if castsShadow {
                    Rectangle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.28), radius: 14, y: 5)
                }
            }
    }
}

/// Catches the input SwiftUI has no gesture for: two-finger scrolling, ⌘/⌥
/// scrolling, trackpad pinch and smart zoom (with the cursor as the anchor),
/// and Space held to compare. It sits behind the canvas as a plain view that
/// never takes a click, and listens through a local event monitor so the
/// canvas’s own drag, hover and double-click keep working.
private struct ViewerInputMonitor: NSViewRepresentable {
    let model: AppModel
    let zoomController: ViewerZoomController

    func makeNSView(context: Context) -> ViewerInputView {
        ViewerInputView()
    }

    func updateNSView(_ view: ViewerInputView, context: Context) {
        view.model = model
        view.zoomController = zoomController
    }
}

private final class ViewerInputView: NSView {
    var model: AppModel?
    var zoomController: ViewerZoomController?
    private var monitor: Any?
    private var resignObserver: (any NSObjectProtocol)?
    private var isComparingWithSpace = false
    private var scrollIsZoom = false

    private static let spaceKeyCode: UInt16 = 49

    // Measured from the top so anchors match SwiftUI's coordinates.
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard let window else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .magnify, .smartMagnify, .keyDown, .keyUp]
        ) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endSpaceCompare() }
        }
    }

    isolated deinit {
        stopMonitoring()
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
        endSpaceCompare()
    }

    /// Returns whether the event was used up, so the rest of the app never sees it.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, let zoomController, let model else { return false }

        switch event.type {
        case .keyDown, .keyUp:
            return handleKey(event, window: window, model: model)
        default:
            break
        }

        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return false }
        let anchor = CGPoint(x: location.x - bounds.midX, y: location.y - bounds.midY)

        switch event.type {
        case .scrollWheel:
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // A gesture keeps zooming or panning as it started, even if the
            // key is let go while momentum coasts.
            if event.phase.contains(.began) || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
                scrollIsZoom = modifiers.contains(.command) || modifiers.contains(.option)
            }
            let isPrecise = event.hasPreciseScrollingDeltas
            if scrollIsZoom {
                let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
                guard delta != 0 else { return true }
                zoomController.zoom(
                    by: ViewerZoomMath.zoomFactor(forScrollDelta: Double(delta), isPrecise: isPrecise),
                    around: anchor
                )
                return true
            }
            guard zoomController.canPan else { return false }
            // Wheel notches come in lines; a line should move a fair distance.
            let step: CGFloat = isPrecise ? 1 : 12
            zoomController.pan(by: CGSize(
                width: event.scrollingDeltaX * step,
                height: event.scrollingDeltaY * step
            ))
            return true
        case .magnify:
            zoomController.zoom(by: 1 + Double(event.magnification), around: anchor)
            return true
        case .smartMagnify:
            zoomController.toggleFitAndActualSize(around: anchor)
            return true
        default:
            return false
        }
    }

    /// Space held while the canvas window is key compares against the original,
    /// unless it is being typed or is meant for a focused control. Returns
    /// whether the event was used up.
    private func handleKey(_ event: NSEvent, window: NSWindow, model: AppModel) -> Bool {
        guard event.keyCode == Self.spaceKeyCode else { return false }

        if event.type == .keyUp {
            guard isComparingWithSpace else { return false }
            endSpaceCompare()
            return true
        }

        if isComparingWithSpace { return true }
        let isPlainSpace = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        let isTyping = window.firstResponder is NSText
        guard isPlainSpace, !isTyping, window.isKeyWindow, !event.isARepeat,
              model.operationMode == .edit,
              model.activeCenterTarget == nil,
              model.sourcePreview != nil,
              model.processedPreview != nil else { return false }
        isComparingWithSpace = true
        model.isHoldingCompare = true
        return true
    }

    private func endSpaceCompare() {
        guard isComparingWithSpace else { return }
        isComparingWithSpace = false
        model?.isHoldingCompare = false
    }
}

private struct ImageCenterOverlay: View {
    let target: EffectCenterTarget
    let position: CGPoint
    let update: (Double, Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard proxy.size.width > 0, proxy.size.height > 0 else { return }
                                let x = min(1, max(0, value.location.x / proxy.size.width))
                                let y = min(1, max(0, value.location.y / proxy.size.height))
                                update(
                                    Double(x),
                                    Double(1 - y)
                                )
                            }
                    )

                CenterTargetMark(tint: target.tint)
                    .position(
                        x: position.x * proxy.size.width,
                        y: (1 - position.y) * proxy.size.height
                    )
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("\(target.title) center")
        .accessibilityValue(
            "X \(Double(position.x).formatted(.percent.precision(.fractionLength(0)))), " +
            "Y \(Double(position.y).formatted(.percent.precision(.fractionLength(0))))"
        )
    }
}

private struct CenterTargetMark: View {
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.46))
                .frame(width: 34, height: 34)
            Circle()
                .strokeBorder(.white.opacity(0.92), lineWidth: 1.5)
                .frame(width: 28, height: 28)
            Circle()
                .strokeBorder(tint, lineWidth: 2)
                .frame(width: 20, height: 20)
            Rectangle()
                .fill(.white.opacity(0.9))
                .frame(width: 36, height: 1)
            Rectangle()
                .fill(.white.opacity(0.9))
                .frame(width: 1, height: 36)
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
        }
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }
}

private struct CenterAdjustmentStatusBar: View {
    @Environment(AppModel.self) private var model

    let target: EffectCenterTarget

    var body: some View {
        let position = model.centerPosition(for: target)

        HStack(spacing: 9) {
            Image(systemName: target.symbol)
                .foregroundStyle(target.tint)
            Text("Adjust \(target.title) Center")
                .fontWeight(.medium)
            Divider()
                .frame(height: 14)
            Text("X \(percentage(position.x))  Y \(percentage(position.y))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Done", action: model.finishCenterAdjustment)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: [])
        }
        .font(.caption)
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.11), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }

    private func percentage(_ value: CGFloat) -> String {
        Double(value).formatted(.percent.precision(.fractionLength(0)))
    }
}

private extension EffectCenterTarget {
    var tint: Color {
        switch self {
        case .vignette: .orange
        case .lensBlur: .cyan
        }
    }
}

private struct ZoomControls: View {
    let zoomController: ViewerZoomController

    var body: some View {
        HStack(spacing: 8) {
            Button {
                zoomController.zoomOut()
            } label: {
                ZoomButtonLabel(systemImage: "minus", width: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom Out")
            .help("Zoom out (⌘−)")

            Slider(
                value: Binding(
                    get: { ViewerZoomMath.sliderPosition(forScale: zoomController.scale) },
                    set: { zoomController.setManualScale(ViewerZoomMath.scale(forSliderPosition: $0)) }
                ),
                in: 0 ... 1
            )
                .accessibilityLabel("Zoom")
                .accessibilityValue(Text(zoomController.scale, format: .percent.precision(.fractionLength(0))))
                .frame(width: 110)

            Button {
                zoomController.zoomIn()
            } label: {
                ZoomButtonLabel(systemImage: "plus", width: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom In")
            .help("Zoom in (⌘+)")

            Divider().frame(height: 14)

            HStack(spacing: 7) {
                Button {
                    zoomController.fit()
                } label: {
                    ZoomButtonLabel("Fit", width: 38)
                }
                .buttonStyle(.plain)
                .help("Fit the image in the window (⌘9)")

                zoomPresets
            }
        }
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
    }
}

extension ZoomControls {
    /// The zoom percentage, which opens the usual zoom levels.
    private var zoomPresets: some View {
        Menu {
            presetButton("Fit", isCurrent: zoomController.isFitted) {
                zoomController.fit()
            }
            ForEach([0.5, 1, 2], id: \.self) { preset in
                presetButton(
                    preset.formatted(.percent.precision(.fractionLength(0))),
                    isCurrent: !zoomController.isFitted && abs(zoomController.scale - preset) < 0.001
                ) {
                    if ViewerZoomMath.isActualSize(preset) {
                        zoomController.actualSize()
                    } else {
                        zoomController.jumpToScale(preset)
                    }
                }
            }
        } label: {
            Text(zoomController.scale, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .fixedSize()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Choose a zoom level")
        .accessibilityLabel("Zoom Level")
        .accessibilityValue(Text(zoomController.scale, format: .percent.precision(.fractionLength(0))))
    }

    private func presetButton(_ title: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isCurrent {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

private struct ZoomButtonLabel: View {
    private let title: String?
    private let systemImage: String?
    private let width: CGFloat

    init(_ title: String, width: CGFloat) {
        self.title = title
        self.systemImage = nil
        self.width = width
    }

    init(systemImage: String, width: CGFloat) {
        self.title = nil
        self.systemImage = systemImage
        self.width = width
    }

    var body: some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
            } else if let title {
                Text(title)
            }
        }
        .frame(width: width, height: 22)
        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
    }
}

private extension NSImage {
    var pixelDimensions: CGSize {
        guard let representation = representations.max(by: {
            ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
        }), representation.pixelsWide > 0, representation.pixelsHigh > 0 else {
            return size
        }
        return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }
}

private struct EditorEmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 50, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text("Open an image to begin")
                .font(.title2.weight(.semibold))
            Text("Adjust the recipe with a live preview, then export when it feels right.")
                .foregroundStyle(.secondary)
            Button("Open Image…") {
                model.chooseImageForEditing()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(40)
    }
}


/// A quiet strip along the foot of the canvas, as in the Finder: what the open
/// image is on the leading side, and what Granular is doing with it on the
/// trailing side. Share and Export live in the window toolbar.
/// An export or a full-size render in progress, or a brief notice, floating
/// above the zoom controls.
private struct EditorActivity: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.isExporting || model.transferRenderCount > 0 {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(model.isExporting ? "Exporting…" : "Preparing full-size image…")
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            } else if let notice = model.editorNotice {
                HStack(spacing: 6) {
                    noticeSymbol(for: notice)
                        .accessibilityHidden(true)
                    Text(notice.message)
                        .truncationMode(.middle)
                    if let action = notice.action {
                        actionButton(action)
                    }
                }
                .transition(.opacity)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            if isShowing {
                Capsule().fill(.regularMaterial)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.editorNotice)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.transferRenderCount > 0)
    }

    private var isShowing: Bool {
        model.isExporting || model.transferRenderCount > 0 || model.editorNotice != nil
    }

    @ViewBuilder
    private func noticeSymbol(for notice: EditorNotice) -> some View {
        if case .processInInstant = notice.action {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: EditorNotice.Action) -> some View {
        switch action {
        case .reveal(let url):
            Button("Show in Finder") {
                model.reveal(url)
            }
            .buttonStyle(.link)
        case .processInInstant(let urls):
            Button("Process All \(urls.count) in Instant") {
                model.processInInstant(urls)
            }
            .buttonStyle(.link)
            .help("Switch to Instant mode and process every image you dropped with this recipe")
        }
    }
}

// MARK: Sharing

/// Share and Export in one place on the viewer, like the share button in
/// Photos: the picker opens at once, Export… first, and the full-size image
/// renders alongside it.
private struct EditorShareButton: View {
    @Environment(AppModel.self) private var model
    @State private var anchor = ShareAnchor()

    var body: some View {
        Button {
            guard let view = anchor.view else { return }
            model.shareProcessedImage(from: view)
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .background {
            ShareAnchorView(anchor: anchor)
        }
        .disabled(model.selectedSourceURL == nil)
        .help("Export or share the full-size image")
        .accessibilityLabel("Share or Export")
    }
}

/// The view the share picker points at.
@MainActor
private final class ShareAnchor {
    weak var view: NSView?
}

private struct ShareAnchorView: NSViewRepresentable {
    let anchor: ShareAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

/// The window’s title, subtitle and proxy icon in Edit mode. They’re set from
/// a view of their own because the subtitle follows the recipe, and reading
/// it in the window’s root view would update the whole window with every
/// change to an adjustment.
struct EditorWindowDocument: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Color.clear
            .navigationTitle(model.editorWindowTitle)
            .navigationSubtitle(model.editorWindowSubtitle)
            .background {
                if model.operationMode == .edit, let url = model.selectedSourceURL {
                    Color.clear
                        .navigationDocument(url)
                }
            }
            .accessibilityHidden(true)
    }
}
