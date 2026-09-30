import Foundation

public enum ViewerZoomMath {
    public static let minimumScale = 0.01
    public static let maximumScale = 8.0

    /// Zoom is measured in device pixels: 100% shows one image pixel per
    /// screen pixel, so one image pixel is two points on a Retina display.
    /// That is the pixel-accurate view a retoucher wants for judging grain
    /// and sharpness, and it makes the percentage mean the same thing on
    /// every display.
    public static let actualSizeScale = 1.0

    // Actual-size landmarks. These are powers of two around 100%, so the
    // buttons and keyboard commands always land on useful, predictable scales
    // regardless of the image's current Fit percentage.
    private static let zoomStops = [
        minimumScale,
        0.015625,
        0.03125,
        0.0625,
        0.125,
        0.25,
        0.5,
        1,
        2,
        4,
        maximumScale
    ]

    public static func fitScale(
        imageWidth: Double,
        imageHeight: Double,
        viewportWidth: Double,
        viewportHeight: Double,
        padding: Double = 48
    ) -> Double {
        guard imageWidth > 0, imageHeight > 0 else { return 1 }
        let availableWidth = max(1, viewportWidth - padding)
        let availableHeight = max(1, viewportHeight - padding)
        return clampedScale(min(availableWidth / imageWidth, availableHeight / imageHeight))
    }

    public static func zoomedIn(from scale: Double) -> Double {
        let current = clampedScale(scale)
        let tolerance = max(0.000_001, current * 0.000_001)
        return zoomStops.first { $0 > current + tolerance } ?? maximumScale
    }

    public static func zoomedOut(from scale: Double) -> Double {
        let current = clampedScale(scale)
        let tolerance = max(0.000_001, current * 0.000_001)
        return zoomStops.last { $0 < current - tolerance } ?? minimumScale
    }

    /// Whether `scale` is 100%, allowing for the rounding a fit or a slider leaves behind.
    public static func isActualSize(_ scale: Double) -> Bool {
        abs(scale - actualSizeScale) < 0.001
    }

    /// The multiplier for one scroll-wheel or trackpad event when ⌘/⌥-scroll
    /// zooms. Wheel notches arrive in lines and trackpad swipes in points, so
    /// the wheel gets a much larger step. Exponential, so zooming in and out
    /// by the same total scroll returns to where it started.
    public static func zoomFactor(forScrollDelta delta: Double, isPrecise: Bool) -> Double {
        exp(delta * (isPrecise ? 0.004 : 0.04))
    }

    /// The pan offset along one axis that keeps the image point under
    /// `anchor` fixed while zooming from `oldScale` to `newScale`. Offset and
    /// anchor are both measured from the centre of the viewport.
    public static func anchoredPanOffset(
        _ offset: Double,
        anchor: Double,
        oldScale: Double,
        newScale: Double
    ) -> Double {
        guard oldScale > 0 else { return offset }
        return anchor - (anchor - offset) * (newScale / oldScale)
    }

    public static func clampedScale(_ scale: Double) -> Double {
        min(maximumScale, max(minimumScale, scale))
    }

    public static func sliderPosition(forScale scale: Double) -> Double {
        let clamped = clampedScale(scale)
        return log(clamped / minimumScale) / log(maximumScale / minimumScale)
    }

    public static func scale(forSliderPosition position: Double) -> Double {
        let clampedPosition = min(1, max(0, position))
        return minimumScale * pow(maximumScale / minimumScale, clampedPosition)
    }

    public static func clampedPanOffset(
        _ proposedOffset: Double,
        displayLength: Double,
        viewportLength: Double
    ) -> Double {
        let limit = max(0, (displayLength - viewportLength) / 2)
        return min(limit, max(-limit, proposedOffset))
    }
}
