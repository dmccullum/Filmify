import CoreGraphics

/// Keeps remembered window frames somewhere the user can still reach them,
/// even if the screens have changed since the frame was saved.
public enum WindowFrameMath {
    /// How much of a window has to overlap a screen for that screen to count.
    private static let minimumOverlap = CGSize(width: 120, height: 60)

    /// The visible frame the window mostly belongs to, or nil if it no longer
    /// overlaps any of them enough to be grabbed.
    public static func bestVisibleFrame(for frame: CGRect, in visibleFrames: [CGRect]) -> CGRect? {
        var best: (frame: CGRect, area: CGFloat)?
        for visible in visibleFrames {
            let overlap = frame.intersection(visible)
            guard !overlap.isNull,
                  overlap.width >= minimumOverlap.width,
                  overlap.height >= minimumOverlap.height else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (visible, area) }
        }
        return best?.frame
    }

    /// Shrinks `frame` to fit inside `visible` (never below `minimumSize`), then
    /// slides it back on screen. The top edge stays put while the height
    /// changes, so the title bar stays where the user left it.
    public static func clamped(
        _ frame: CGRect,
        to visible: CGRect,
        minimumSize: CGSize = .zero
    ) -> CGRect {
        var result = frame
        result.size.width = max(min(frame.width, visible.width), min(minimumSize.width, visible.width))
        result.size.height = max(min(frame.height, visible.height), min(minimumSize.height, visible.height))
        result.origin.y = frame.maxY - result.height
        result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }
}
