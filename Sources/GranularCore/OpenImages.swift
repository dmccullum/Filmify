import Foundation

/// Bookkeeping for the images open in Edit mode's filmstrip and the recent
/// images list. The recipe is shared, so the list only tracks files.
public enum OpenImages {
    /// Adds newly opened images after the ones already open, in the order
    /// given, skipping any that are open already.
    public static func appending(_ urls: [URL], to open: [URL]) -> [URL] {
        var result = open
        var seen = Set(open.map(\.standardizedFileURL))
        for url in urls where seen.insert(url.standardizedFileURL).inserted {
            result.append(url)
        }
        return result
    }

    /// The image to show once the one at `index` has closed: the image that
    /// took its place, or the new last one when it was at the end.
    public static func selectionAfterClosing(at index: Int, remaining: [URL]) -> URL? {
        guard !remaining.isEmpty else { return nil }
        return remaining[min(max(index, 0), remaining.count - 1)]
    }

    /// The image `offset` places along from `url`, or nil past either end;
    /// the filmstrip stops at its ends rather than wrapping around.
    public static func neighbor(of url: URL?, offset: Int, in open: [URL]) -> URL? {
        guard let url, let index = open.firstIndex(of: url) else { return nil }
        let target = index + offset
        return open.indices.contains(target) ? open[target] : nil
    }

    /// Moves `item` to the front of a most-recent-first list, keeping at most `limit`.
    public static func recents<Item>(
        _ list: [Item],
        adding item: Item,
        limit: Int,
        matching isSame: (Item, Item) -> Bool
    ) -> [Item] {
        Array(([item] + list.filter { !isSame($0, item) }).prefix(max(limit, 0)))
    }
}
