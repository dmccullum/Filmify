import AppKit
import GranularCore
import Observation
import SwiftUI

@MainActor
@Observable
final class ViewerZoomController {
    private(set) var scale = 1.0
    private(set) var fitScale = 1.0
    private(set) var isFitted = true

    func updateFitScale(_ scale: Double) {
        fitScale = ViewerZoomMath.clampedScale(scale)
        if isFitted {
            self.scale = fitScale
        }
    }

    func zoomIn() {
        setManualScale(ViewerZoomMath.zoomedIn(from: scale))
    }

    func zoomOut() {
        setManualScale(ViewerZoomMath.zoomedOut(from: scale))
    }

    func setManualScale(_ scale: Double) {
        isFitted = false
        self.scale = ViewerZoomMath.clampedScale(scale)
    }

    func fit() {
        isFitted = true
        scale = fitScale
    }

    func resetForNewImage() {
        fit()
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

struct EditModeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoomController = ViewerZoomController()
    @FocusState private var isCanvasFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    if let image = model.previewImage {
                        ZoomableImageCanvas(
                            image: image,
                            imagePixelSize: model.sourcePreview?.pixelDimensions ?? image.pixelDimensions,
                            zoomController: zoomController
                        )
                        .id(model.selectedSourceURL)

                        VStack {
                            ZStack {
                                if let target = model.activeCenterTarget {
                                    CenterAdjustmentStatusBar(target: target)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }

                                HStack {
                                    Spacer()
                                    if model.activeCenterTarget == nil,
                                       model.sourcePreview != nil,
                                       model.processedPreview != nil {
                                        Button {
                                            model.showOriginal.toggle()
                                        } label: {
                                            Label(
                                                model.showOriginal ? "Original" : "Granular",
                                                systemImage: model.showOriginal ? "eye.slash" : "eye"
                                            )
                                        }
                                        .buttonStyle(.glass)
                                    }
                                }
                            }
                            Spacer()
                            ZoomControls(zoomController: zoomController)
                        }
                        .padding(16)
                    } else {
                        EditorEmptyState()
                    }

                    // Edits render live; only the first render of a newly opened photo is slow enough to show.
                    if model.isRenderingPreview, model.processedPreview == nil {
                        ProgressView()
                            .controlSize(.small)
                            .padding(9)
                            .background(.regularMaterial, in: Circle())
                    }
                }
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
                .dropDestination(for: URL.self) { urls, _ in
                    model.openForEditing(urls)
                    return !urls.isEmpty
                } isTargeted: { targeted in
                    model.isDropTargeted = targeted
                }

                if model.openImageURLs.count > 1 {
                    EditorFilmstrip()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                EditorStatusBar()
            }

            AdjustmentsInspector()
                .environment(model)
                .frame(width: 310)
                .background(.bar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusedSceneValue(\.granularViewerZoomController, zoomController)
        .onChange(of: model.selectedSourceURL) { _, _ in
            zoomController.resetForNewImage()
            model.finishCenterAdjustment()
        }
        .onChange(of: model.recipe.lightShaping.isEnabled) { _, enabled in
            dismissCenterAdjustment(.vignette, when: enabled)
        }
        .onChange(of: model.recipe.lensBlur.isEnabled) { _, enabled in
            dismissCenterAdjustment(.lensBlur, when: enabled)
        }
        .onChange(of: model.selectedSourceURL, initial: true) { previous, url in
            // A newly opened image takes focus, so ⌘C copies it straight away.
            // (On first appearance, `previous` is the current image.)
            if url != nil, previous == nil || previous == url {
                isCanvasFocused = true
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.openImageURLs.count > 1)
        .onExitCommand(perform: model.finishCenterAdjustment)
        .onDisappear(perform: model.finishCenterAdjustment)
    }

    private func dismissCenterAdjustment(_ target: EffectCenterTarget, when enabled: Bool) {
        if !enabled, model.activeCenterTarget == target {
            model.finishCenterAdjustment()
        }
    }
}

private struct ZoomableImageCanvas: View {
    @Environment(AppModel.self) private var model

    let image: NSImage
    let imagePixelSize: CGSize
    let zoomController: ViewerZoomController
    @State private var gestureStartZoom = 1.0
    @State private var isMagnifying = false
    @State private var panOffset = CGSize.zero
    @State private var dragStartOffset: CGSize?

    var body: some View {
        GeometryReader { proxy in
            let fitScale = min(
                ViewerZoomMath.fitScale(
                    imageWidth: Double(imagePixelSize.width),
                    imageHeight: Double(imagePixelSize.height),
                    viewportWidth: Double(proxy.size.width),
                    viewportHeight: Double(proxy.size.height)
                ),
                ViewerZoomMath.maximumScale
            )
            let displaySize = CGSize(
                width: imagePixelSize.width * CGFloat(zoomController.scale),
                height: imagePixelSize.height * CGFloat(zoomController.scale)
            )
            let canPan = displaySize.width > proxy.size.width || displaySize.height > proxy.size.height

            ZStack {
                Color.clear
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .shadow(color: .black.opacity(0.28), radius: 14, y: 5)
                        .contentShape(Rectangle())
                        .gesture(panGesture(displaySize: displaySize, viewportSize: proxy.size, canPan: canPan))
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
                .offset(panOffset)
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
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if !isMagnifying {
                            gestureStartZoom = zoomController.scale
                            isMagnifying = true
                        }
                        zoomController.setManualScale(gestureStartZoom * value.magnification)
                    }
                    .onEnded { _ in
                        isMagnifying = false
                    }
            )
            .onChange(of: fitScale, initial: true) { _, newFitScale in
                zoomController.updateFitScale(newFitScale)
                if zoomController.isFitted {
                    panOffset = .zero
                }
            }
            .onChange(of: zoomController.scale) { _, _ in
                if zoomController.isFitted {
                    panOffset = .zero
                } else {
                    panOffset = clampedOffset(
                        panOffset,
                        displaySize: displaySize,
                        viewportSize: proxy.size
                    )
                }
            }
            .onDisappear {
                NSCursor.arrow.set()
            }
        }
    }

    private func panGesture(displaySize: CGSize, viewportSize: CGSize, canPan: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard canPan, model.activeCenterTarget == nil else { return }
                if dragStartOffset == nil {
                    dragStartOffset = panOffset
                }
                let start = dragStartOffset ?? .zero
                panOffset = clampedOffset(
                    CGSize(
                        width: start.width + value.translation.width,
                        height: start.height + value.translation.height
                    ),
                    displaySize: displaySize,
                    viewportSize: viewportSize
                )
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

    private func clampedOffset(
        _ proposed: CGSize,
        displaySize: CGSize,
        viewportSize: CGSize
    ) -> CGSize {
        CGSize(
            width: CGFloat(ViewerZoomMath.clampedPanOffset(
                Double(proposed.width),
                displayLength: Double(displaySize.width),
                viewportLength: Double(viewportSize.width)
            )),
            height: CGFloat(ViewerZoomMath.clampedPanOffset(
                Double(proposed.height),
                displayLength: Double(displaySize.height),
                viewportLength: Double(viewportSize.height)
            ))
        )
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

            Divider().frame(height: 14)

            HStack(spacing: 7) {
                Button {
                    zoomController.fit()
                } label: {
                    ZoomButtonLabel("Fit", width: 38)
                }
                .buttonStyle(.plain)

                Text(zoomController.scale, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .fixedSize()
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

private struct EditorStatusBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHoveringSource = false

    var body: some View {
        HStack(spacing: 12) {
            // The file name lives in the window title now; this keeps its size
            // and place in the set, and the way to close it.
            if model.selectedSourceURL != nil {
                HStack(spacing: 6) {
                    Button {
                        model.closeEditorImage()
                    } label: {
                        ZStack {
                            Image(systemName: "photo")
                                .font(.system(size: 12))
                                .opacity(isHoveringSource ? 0 : 1)

                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .opacity(isHoveringSource ? 1 : 0)
                        }
                        .frame(width: 17, height: 17)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Close Image")
                    .help("Close image")

                    Text(imageSummary)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onHover { isHovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHoveringSource = isHovering
                    }
                }
            } else {
                Text("No image open")
                    .foregroundStyle(.secondary)
            }

            EditorActivity()

            Spacer(minLength: 20)

            shareButton

            if model.openImageURLs.count > 1 {
                Button("Export All…") {
                    model.exportAllImages()
                }
                .buttonStyle(.glass)
                .disabled(model.batchExport != nil)
                .help("Export every open image with this recipe")
            }

            Button("Export…") {
                model.exportEditedImage()
            }
            .buttonStyle(.glassProminent)
            .disabled(model.selectedSourceURL == nil || model.isExporting)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.editorNotice)
    }

    /// Pixel size, and the image’s place among those open.
    private var imageSummary: String {
        var parts: [String] = []
        if let size = model.sourcePreview?.pixelDimensions {
            parts.append("\(Int(size.width)) × \(Int(size.height))")
        }
        if model.openImageURLs.count > 1,
           let url = model.selectedSourceURL,
           let index = model.openImageURLs.firstIndex(of: url) {
            parts.append("\(index + 1) of \(model.openImageURLs.count)")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var shareButton: some View {
        let label = Label("Share", systemImage: "square.and.arrow.up")
        if let source = model.selectedSourceURL, let preview = model.previewImage {
            ShareLink(
                item: model.processedImageItem(for: source),
                preview: SharePreview(model.exportFileName(for: source), image: Image(nsImage: preview))
            ) {
                label
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .help("Share the full-size image")
        } else {
            Button {} label: { label }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .disabled(true)
        }
    }
}

/// Export progress, a full-size render in progress, or a brief confirmation.
private struct EditorActivity: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let progress = model.batchExport {
            HStack(spacing: 8) {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .frame(width: 90)
                Text("Exporting \(min(progress.completed + 1, progress.total)) of \(progress.total)…")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button {
                    model.cancelBatchExport()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Stop Exporting")
                .help("Stop after the image being exported")
            }
            .accessibilityElement(children: .combine)
        } else if model.isExporting || model.transferRenderCount > 0 {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(model.isExporting ? "Exporting…" : "Preparing full-size image…")
                    .foregroundStyle(.secondary)
            }
        } else if let notice = model.editorNotice {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(notice.message)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                if let url = notice.revealURL {
                    Button("Show in Finder") {
                        model.reveal(url)
                    }
                    .buttonStyle(.link)
                }
            }
            .transition(.opacity)
        }
    }
}
