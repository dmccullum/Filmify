import Foundation

extension AppModel {
    /// Whether the viewer is showing the original: toggled on with `\` or a
    /// click on Before/After, or peeked at while the compare control is held.
    var isShowingOriginal: Bool {
        showOriginal || isHoldingCompare
    }
}
