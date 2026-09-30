import Foundation

/// A run of images processed together: one drop in Instant mode, or one burst
/// of arrivals in a watched folder. Drops made while a batch is still running
/// join it, so the counter keeps reading as a single roll.
public struct ProcessingBatch: Equatable, Sendable {
    public private(set) var total: Int
    public private(set) var succeeded = 0
    public private(set) var failed = 0
    public private(set) var outputs: [URL] = []
    /// Set when the person cancels; the image in the gate still finishes.
    public var isCancelled = false

    public init(total: Int) {
        self.total = max(0, total)
    }

    public var completed: Int { succeeded + failed }

    public var isFinished: Bool { completed >= total }

    /// The image being worked on now, counting from one, as in “3 of 12”.
    public var position: Int { min(total, completed + 1) }

    /// Progress for a bar, counting both results as done.
    public var fractionComplete: Double {
        total == 0 ? 1 : min(1, Double(completed) / Double(total))
    }

    /// Adds a further drop to the batch that is already running.
    public mutating func add(_ count: Int) {
        total += max(0, count)
    }

    public mutating func recordSuccess(output: URL) {
        succeeded += 1
        outputs.append(output)
    }

    public mutating func recordFailure() {
        failed += 1
    }

    /// One line for a notification, e.g. “12 images processed with Portra 400 · 1 failed”.
    public func summary(recipeName: String?) -> String {
        var parts: [String] = []
        if succeeded > 0 || failed == 0 {
            var line = "\(succeeded) \(succeeded == 1 ? "image" : "images") processed"
            if let recipeName, !recipeName.isEmpty {
                line += " with \(recipeName)"
            }
            parts.append(line)
            if failed > 0 {
                parts.append("\(failed) failed")
            }
        } else {
            parts.append("\(failed) \(failed == 1 ? "image" : "images") couldn’t be processed")
        }
        if isCancelled, completed < total {
            parts.append("\(total - completed) cancelled")
        }
        return parts.joined(separator: " · ")
    }
}

/// Most-recent-first folder history, as in a path pop-up’s recent list.
public enum RecentFolders {
    public static let limit = 5

    /// Moves `folder` to the front, dropping duplicates and anything past the limit.
    public static func adding(_ folder: URL, to folders: [URL], limit: Int = limit) -> [URL] {
        let key = folder.standardizedFileURL.path
        let others = folders.filter { $0.standardizedFileURL.path != key }
        return Array(([folder] + others).prefix(max(1, limit)))
    }
}
