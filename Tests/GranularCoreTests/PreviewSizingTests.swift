import Testing
@testable import GranularCore

@Test func previewsRenderNoLargerThanTheyAreShown() {
    // Rounded up to a step, so resizing the window a little doesn't re-render.
    #expect(PreviewSizing.renderDimension(displayedLongEdge: 1_800, sourceLongEdge: 6_000) == 2_048)
    #expect(PreviewSizing.renderDimension(displayedLongEdge: 2_048, sourceLongEdge: 6_000) == 2_048)
    #expect(PreviewSizing.renderDimension(displayedLongEdge: 10, sourceLongEdge: 6_000) == 256)
    // Never past the image itself, however far it's zoomed in.
    #expect(PreviewSizing.renderDimension(displayedLongEdge: 12_000, sourceLongEdge: 6_000) == 6_000)
    #expect(PreviewSizing.renderDimension(displayedLongEdge: 1_000, sourceLongEdge: 800) == 800)
    #expect(PreviewSizing.renderDimension(displayedLongEdge: 3_000, sourceLongEdge: nil) == 3_072)
}

@Test func previewsStaySmallWhileAdjustingAndSharpenOnceSettled() {
    #expect(PreviewSizing.interactiveDimension(for: 6_000, limit: 2_400) == 2_400)
    #expect(PreviewSizing.interactiveDimension(for: 1_536, limit: 2_400) == 1_536)

    #expect(PreviewSizing.needsSharperRender(rendered: 2_400, wanted: 6_000))
    #expect(!PreviewSizing.needsSharperRender(rendered: 6_000, wanted: 6_000))
    #expect(!PreviewSizing.needsSharperRender(rendered: 3_072, wanted: 2_048))
    // Nothing rendered yet is a first render's job, not a sharper one's.
    #expect(!PreviewSizing.needsSharperRender(rendered: 0, wanted: 2_048))
}
