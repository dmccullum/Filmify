import Foundation
import Testing
@testable import GranularCore

private func image(_ name: String) -> URL {
    URL(fileURLWithPath: "/Photos/\(name).jpg")
}

@Test func recentImagesPutTheNewestFirstWithoutDuplicates() {
    let list = [image("a"), image("b"), image("c")]

    let result = OpenImages.recents(list, adding: image("c"), limit: 3, matching: ==)
    #expect(result == [image("c"), image("a"), image("b")])

    let capped = OpenImages.recents(list, adding: image("d"), limit: 3, matching: ==)
    #expect(capped == [image("d"), image("a"), image("b")])
}
