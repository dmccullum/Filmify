import Foundation

/// Bookkeeping for the recent images list behind File ▸ Open Recent and the
/// Dock menu.
public enum OpenImages {
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
