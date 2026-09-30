import Testing
@testable import GranularCore

@Test func anchoredZoomKeepsTheImagePointUnderTheCursorFixed() {
    // A point 100pt right of the viewport centre, image centred (offset 0), zooming 1x -> 2x.
    let offset = ViewerZoomMath.anchoredPanOffset(0, anchor: 100, oldScale: 1, newScale: 2)
    #expect(offset == -100)

    // The image point under the anchor before and after must be the same.
    let before = (100.0 - 40) / 0.5
    let after = (100.0 - ViewerZoomMath.anchoredPanOffset(40, anchor: 100, oldScale: 0.5, newScale: 1.5)) / 1.5
    #expect(abs(before - after) < 0.000_001)
}

@Test func anchoredZoomAroundTheCentreLeavesACentredImageAlone() {
    #expect(ViewerZoomMath.anchoredPanOffset(0, anchor: 0, oldScale: 0.25, newScale: 4) == 0)
}

@Test func scrollZoomIsExponentialSoOppositeScrollsCancel() {
    let up = ViewerZoomMath.zoomFactor(forScrollDelta: 30, isPrecise: true)
    let down = ViewerZoomMath.zoomFactor(forScrollDelta: -30, isPrecise: true)
    #expect(up > 1)
    #expect(abs(up * down - 1) < 0.000_001)
    #expect(ViewerZoomMath.zoomFactor(forScrollDelta: 1, isPrecise: false) > ViewerZoomMath.zoomFactor(forScrollDelta: 1, isPrecise: true))
}

@Test func actualSizeToleratesRoundingFromFitAndSlider() {
    #expect(ViewerZoomMath.isActualSize(1))
    #expect(ViewerZoomMath.isActualSize(1.0004))
    #expect(!ViewerZoomMath.isActualSize(0.5))
    #expect(!ViewerZoomMath.isActualSize(1.01))
}
