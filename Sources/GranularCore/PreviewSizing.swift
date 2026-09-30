import Foundation

/// How large Edit mode renders its live preview: no larger than the viewer
/// shows it, and smaller still while the recipe is changing, so a slider keeps
/// up and a sharper render follows once it settles.
public enum PreviewSizing {
    /// Previews are sized in steps, so a small change in window size or zoom
    /// doesn't render again.
    public static let step = 256.0

    /// The long edge to render for an image shown `displayedLongEdge` screen
    /// pixels long: rounded up to a step, and never past the image's own size.
    public static func renderDimension(displayedLongEdge: Double, sourceLongEdge: Double?) -> Double {
        let stepped = max(step, (displayedLongEdge / step).rounded(.up) * step)
        guard let sourceLongEdge, sourceLongEdge > 0 else { return stepped }
        return min(stepped, sourceLongEdge)
    }

    /// The long edge to render while changes are still arriving.
    public static func interactiveDimension(for renderDimension: Double, limit: Double) -> Double {
        min(renderDimension, limit)
    }

    /// Whether the preview on screen is soft for how large it's shown, and a
    /// sharper one should follow.
    public static func needsSharperRender(rendered: Double, wanted: Double) -> Bool {
        rendered > 0 && rendered < wanted
    }
}
