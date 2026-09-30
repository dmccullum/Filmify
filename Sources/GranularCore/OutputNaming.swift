import Foundation

/// Names for exported files, built from a template such as `{name} — Granular`.
///
/// Tokens: `{name}` is the source file’s name, `{recipe}` the recipe’s name,
/// `{date}` today’s date as yyyy-MM-dd, and `{counter}` a number that starts
/// at 001 and counts up until the name is free in the folder. Without
/// `{counter}`, a taken name gets " 2", " 3" and so on.
public enum OutputNaming {
    /// Granular’s original naming, so an untouched template changes nothing.
    public static let defaultTemplate = "{name} — Granular"
    public static let tokens = ["{name}", "{recipe}", "{date}", "{counter}"]

    public static func hasCounter(_ template: String) -> Bool {
        template.range(of: "{counter}", options: .caseInsensitive) != nil
    }

    /// The file name (without extension) a template produces.
    public static func render(
        template: String,
        name: String,
        recipe: String,
        date: Date = Date(),
        counter: Int = 1
    ) -> String {
        let effective = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultTemplate
            : template
        let rendered = sanitized(expand(effective, name: name, recipe: recipe, date: date, counter: counter))
        if !rendered.isEmpty { return rendered }
        return sanitized(expand(defaultTemplate, name: name, recipe: recipe, date: date, counter: counter))
    }

    /// The first free URL for an output, in the way the template asks for.
    public static func uniqueURL(
        template: String,
        name: String,
        recipe: String,
        date: Date = Date(),
        folder: URL,
        fileExtension: String,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        func url(_ base: String) -> URL {
            folder.appendingPathComponent(base).appendingPathExtension(fileExtension)
        }
        if hasCounter(template) {
            var counter = 1
            while exists(url(render(template: template, name: name, recipe: recipe, date: date, counter: counter))) {
                counter += 1
            }
            return url(render(template: template, name: name, recipe: recipe, date: date, counter: counter))
        }
        let base = render(template: template, name: name, recipe: recipe, date: date)
        var candidate = url(base)
        var suffix = 2
        while exists(candidate) {
            candidate = url("\(base) \(suffix)")
            suffix += 1
        }
        return candidate
    }

    // Tokens are replaced in a single pass, so a file called "{date}" stays
    // "{date}" instead of being expanded a second time.
    private static func expand(_ template: String, name: String, recipe: String, date: Date, counter: Int) -> String {
        var output = ""
        var remaining = template[...]
        while let open = remaining.firstIndex(of: "{") {
            output += remaining[..<open]
            let afterOpen = remaining.index(after: open)
            guard let close = remaining[afterOpen...].firstIndex(of: "}") else {
                remaining = remaining[open...]
                break
            }
            switch remaining[afterOpen ..< close].lowercased() {
            case "name": output += name
            case "recipe": output += recipe
            case "date": output += dateString(date)
            case "counter": output += String(format: "%03d", counter)
            default: output += remaining[open ... close]
            }
            remaining = remaining[remaining.index(after: close)...]
        }
        return output + remaining
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Keeps a name usable as a file name: no path separators, not hidden,
    /// and short enough to leave room for the extension.
    private static func sanitized(_ name: String) -> String {
        var cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        if cleaned.count > 200 { cleaned = String(cleaned.prefix(200)) }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
