import SwiftUI
import UIKit

/// Where the photo sits on screen and how far it's zoomed, shared with the
/// views drawn over it.
@MainActor
@Observable
final class CanvasGeometry {
    /// The photo's frame in the canvas, following every pinch and pan.
    var imageFrame: CGRect = .zero
}

/// The photo being edited, zoomed and panned as in Photos: pinch, drag,
/// double-tap to zoom in or back out, and hold to see the original.
struct PhotoCanvas: UIViewRepresentable {
    let image: CGImage?
    /// The part of the canvas the photo fits into at rest; it can be panned
    /// out under the controls once zoomed.
    let insets: UIEdgeInsets
    let geometry: CanvasGeometry
    let onPressing: (Bool) -> Void
    /// The photo's long edge on screen in pixels, once a zoom settles.
    let onDisplaySize: (CGFloat) -> Void

    func makeUIView(context: Context) -> PhotoScrollView {
        PhotoScrollView()
    }

    func updateUIView(_ view: PhotoScrollView, context: Context) {
        view.geometry = geometry
        view.onPressing = onPressing
        view.onDisplaySize = onDisplaySize
        view.fitInsets = insets
        view.setImage(image)
    }
}

final class PhotoScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var imageAspect: CGFloat?
    private var fittedBounds: CGRect = .zero
    var geometry: CanvasGeometry?
    var onPressing: (Bool) -> Void = { _ in }
    var onDisplaySize: (CGFloat) -> Void = { _ in }
    var fitInsets: UIEdgeInsets = .zero {
        didSet {
            if !fitInsets.isClose(to: oldValue) { refit() }
        }
    }

    init() {
        super.init(frame: .zero)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        minimumZoomScale = 1
        maximumZoomScale = 8
        bouncesZoom = true
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Photo"
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.2
        hold.delegate = self
        addGestureRecognizer(hold)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: CGImage?) {
        let previous = imageView.image
        imageView.image = image.map { UIImage(cgImage: $0) }
        let aspect = image.map { CGFloat($0.width) / CGFloat(max(1, $0.height)) }
        // A new render of the same photo keeps the zoom; a different photo starts over.
        if let aspect, let imageAspect, abs(aspect - imageAspect) < 0.01, previous != nil { return }
        imageAspect = aspect
        refit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedBounds.size { refit() }
    }

    /// Fits the photo into the space left by the controls, at no zoom.
    private func refit() {
        guard let imageAspect, bounds.width > 0, bounds.height > 0 else {
            report()
            return
        }
        fittedBounds = bounds
        let area = bounds.inset(by: fitInsets)
        var size = CGSize(width: area.width, height: area.width / imageAspect)
        if size.height > area.height {
            size = CGSize(width: area.height * imageAspect, height: area.height)
        }
        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        centerContent()
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        report()
        reportDisplaySize()
    }

    /// Keeps a photo smaller than the space centred in it.
    private func centerContent() {
        let area = bounds.inset(by: fitInsets)
        let horizontal = max(0, (area.width - contentSize.width) / 2)
        let vertical = max(0, (area.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(
            top: fitInsets.top + vertical,
            left: fitInsets.left + horizontal,
            bottom: fitInsets.bottom + vertical,
            right: fitInsets.right + horizontal
        )
    }

    private func report() {
        let frame = imageView.image == nil ? .zero : imageView.frame.offsetBy(dx: -contentOffset.x, dy: -contentOffset.y)
        if geometry?.imageFrame != frame {
            geometry?.imageFrame = frame
        }
    }

    private func reportDisplaySize() {
        let longEdge = max(imageView.frame.width, imageView.frame.height)
        guard longEdge > 0 else { return }
        onDisplaySize(longEdge * traitCollection.displayScale)
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        report()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        report()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        reportDisplaySize()
    }

    // MARK: Gestures

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let scale: CGFloat = 3
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began: onPressing(true)
        case .ended, .cancelled, .failed: onPressing(false)
        default: break
        }
    }
}

private extension UIEdgeInsets {
    func isClose(to other: UIEdgeInsets) -> Bool {
        abs(top - other.top) < 1 && abs(left - other.left) < 1
            && abs(bottom - other.bottom) < 1 && abs(right - other.right) < 1
    }
}

extension PhotoScrollView: UIGestureRecognizerDelegate {
    /// Holding to compare works mid-zoom without stopping it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// The crosshair for an effect's centre, dragged anywhere over the photo.
/// Double-tap puts it back where the recipe has it.
struct CenterHandle: View {
    let title: String
    let geometry: CanvasGeometry
    /// From 0 to 1 across the photo, with y measured up from the bottom, as
    /// the renderer takes it.
    @Binding var center: CGPoint
    let recipeCenter: CGPoint

    @State private var isDragging = false

    var body: some View {
        let frame = geometry.imageFrame
        if frame.width > 0 {
            CenterMark(isActive: isDragging)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .position(
                    x: frame.minX + center.x * frame.width,
                    y: frame.minY + (1 - center.y) * frame.height
                )
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(PhotoCanvas.space))
                        .onChanged { value in
                            isDragging = true
                            center = CGPoint(
                                x: min(1, max(0, (value.location.x - frame.minX) / frame.width)),
                                y: min(1, max(0, 1 - (value.location.y - frame.minY) / frame.height))
                            )
                        }
                        .onEnded { _ in isDragging = false }
                )
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    withAnimation(.smooth) { center = recipeCenter }
                })
                .sensoryFeedback(.impact(weight: .light), trigger: isDragging) { _, dragging in dragging }
                .accessibilityElement()
                .accessibilityLabel("\(title) Center")
                .accessibilityValue("X \(percent(center.x)), Y \(percent(center.y))")
                .accessibilityAction(named: "Reset to Recipe Value") { center = recipeCenter }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    private func percent(_ value: CGFloat) -> String {
        Double(value).formatted(.percent.precision(.fractionLength(0)))
    }
}

extension PhotoCanvas {
    static let space = "canvas"
}

private struct CenterMark: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.3))
                .frame(width: 30, height: 30)
            Circle()
                .strokeBorder(.white, lineWidth: 1.5)
                .frame(width: 30, height: 30)
            Rectangle().fill(.white).frame(width: 10, height: 1.5)
            Rectangle().fill(.white).frame(width: 1.5, height: 10)
        }
        .scaleEffect(isActive ? 1.2 : 1)
        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
        .animation(.spring(duration: 0.25), value: isActive)
    }
}
