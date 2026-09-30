import AppIntents
import AppKit
import GranularCore
import Foundation

/// Hands the app’s one model to the parts of macOS that call in from outside
/// its windows: Shortcuts actions and the Services menu. Runs as the app is
/// created, so it’s in place even when one of those is what launched Granular.
@MainActor
enum SystemIntegration {
    static func connect(_ model: AppModel) {
        AppDependencyManager.shared.add(dependency: model)
        ImageServiceProvider.shared.model = model
    }
}

// Shortcuts, the Services menu and the menu bar item.
extension AppModel {
    /// The newest finished frames, for the menu bar item.
    func recentOutputs(limit: Int = 5) -> [URL] {
        Array(jobs.lazy.compactMap { job -> URL? in
            if case .finished(let url) = job.state { return url }
            return nil
        }.prefix(limit))
    }

    /// Processes images for a Shortcuts action with a recipe of its choosing
    /// and the Output settings, into `destination`. Unlike a drop, it stays off
    /// the film strip: the images and results belong to the shortcut.
    func processForShortcut(_ sources: [URL], recipe: FilmRecipe, destination: URL) async throws -> [URL] {
        guard let processingService else {
            throw ShortcutError.engineUnavailable(startupError)
        }
        var outputs: [URL] = []
        for source in sources {
            let output = try await processingService.process(
                sourceURL: source,
                destinationFolder: destination,
                recipe: recipe,
                options: outputOptions
            )
            outputs.append(output)
        }
        statusMessage = outputs.count == 1
            ? "Shortcuts processed \(outputs[0].lastPathComponent)"
            : "Shortcuts processed \(outputs.count) images"
        return outputs
    }
}

enum ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case noImages
    case noOutputFolder
    case folderUnavailable(String)
    case engineUnavailable(String?)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noImages:
            "None of those files are images Granular can process. Use JPEG, HEIC, PNG or TIFF."
        case .noOutputFolder:
            "Choose an Instant output folder in Granular, or pick an Output Folder in this action."
        case .folderUnavailable(let name):
            "The folder “\(name)” isn’t available. Choose it again."
        case .engineUnavailable(let reason):
            "Granular’s image engine couldn’t start. \(reason ?? "")"
        }
    }
}
