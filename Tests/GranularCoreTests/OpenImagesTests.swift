import Foundation
import Testing
@testable import GranularCore

private func image(_ name: String) -> URL {
    URL(fileURLWithPath: "/Photos/\(name).jpg")
}

@Test func openingImagesAppendsInOrderAndSkipsOnesAlreadyOpen() {
    let open = [image("a"), image("b")]
    let reopened = URL(fileURLWithPath: "/Photos/./b.jpg")

    let result = OpenImages.appending([image("c"), reopened, image("c"), image("d")], to: open)

    #expect(result == [image("a"), image("b"), image("c"), image("d")])
}

@Test func closingAnImageShowsTheOneThatTookItsPlace() {
    let remaining = [image("a"), image("c")]

    #expect(OpenImages.selectionAfterClosing(at: 1, remaining: remaining) == image("c"))
    #expect(OpenImages.selectionAfterClosing(at: 2, remaining: remaining) == image("c"))
    #expect(OpenImages.selectionAfterClosing(at: 0, remaining: remaining) == image("a"))
    #expect(OpenImages.selectionAfterClosing(at: 0, remaining: []) == nil)
}

@Test func movingThroughTheFilmstripStopsAtItsEnds() {
    let open = [image("a"), image("b"), image("c")]

    #expect(OpenImages.neighbor(of: image("b"), offset: 1, in: open) == image("c"))
    #expect(OpenImages.neighbor(of: image("b"), offset: -1, in: open) == image("a"))
    #expect(OpenImages.neighbor(of: image("c"), offset: 1, in: open) == nil)
    #expect(OpenImages.neighbor(of: image("a"), offset: -1, in: open) == nil)
    #expect(OpenImages.neighbor(of: nil, offset: 1, in: open) == nil)
    #expect(OpenImages.neighbor(of: image("z"), offset: 1, in: open) == nil)
}

@Test func recentImagesPutTheNewestFirstWithoutDuplicates() {
    let list = [image("a"), image("b"), image("c")]

    let result = OpenImages.recents(list, adding: image("c"), limit: 3, matching: ==)
    #expect(result == [image("c"), image("a"), image("b")])

    let capped = OpenImages.recents(list, adding: image("d"), limit: 3, matching: ==)
    #expect(capped == [image("d"), image("a"), image("b")])
}
