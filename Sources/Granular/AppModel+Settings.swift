import AppKit
import GranularCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum SettingsKey {
    static let outputOptions = "settings.outputOptions"
    static let opensInLastUsedMode = "settings.opensInLastUsedMode"
    static let menuBarVisibility = "settings.menuBarVisibility"
    static let lastMode = "settings.lastMode"
    static let wasWatching = "settings.wasWatching"
    static func windowFrame(_ mode: OperationMode) -> String { "window.frame.\(mode.rawValue)" }
}

/// When Granular’s menu bar item is shown.
enum MenuBarVisibility: String, CaseIterable, Identifiable {
    case always
    case whileWatching

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: "Always"
        case .whileWatching: "While Watching"
        }
    }
}

// Remembering settings between launches.
extension AppModel {
    /// Reads everything saved by an earlier launch. Runs before anything else
    /// in `init`, so the window and the first render start from it.
    func restoreSettings() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: SettingsKey.outputOptions),
           let saved = try? JSONDecoder().decode(OutputOptions.self, from: data) {
            outputOptions = saved
        }
        if defaults.object(forKey: SettingsKey.opensInLastUsedMode) != nil {
            opensInLastUsedMode = defaults.bool(forKey: SettingsKey.opensInLastUsedMode)
        }
        if let raw = defaults.string(forKey: SettingsKey.menuBarVisibility),
           let saved = MenuBarVisibility(rawValue: raw) {
            menuBarVisibility = saved
        }

        for mode in OperationMode.allCases {
            if let values = defaults.array(forKey: SettingsKey.windowFrame(mode)) as? [Double],
               values.count == 4 {
                savedWindowFrames[mode] = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            }
        }

        if opensInLastUsedMode,
           let raw = defaults.string(forKey: SettingsKey.lastMode),
           let mode = OperationMode(rawValue: raw) {
            operationMode = mode
            // Nothing is switching: the window simply opens in this mode.
            isSettlingWindow = false
            arrivingLayoutSize = nil
        }
    }

    func saveOutputOptions() {
        guard let data = try? JSONEncoder().encode(outputOptions) else { return }
        UserDefaults.standard.set(data, forKey: SettingsKey.outputOptions)
    }

    /// The file name the Save panel offers for an Edit-mode export.
    func suggestedExportName(for sourceURL: URL, type: UTType) -> String {
        let name = OutputNaming.render(
            template: outputOptions.filenameTemplate,
            name: sourceURL.deletingPathExtension().lastPathComponent,
            recipe: recipe.name
        )
        return name + "." + (type.preferredFilenameExtension ?? "tiff")
    }
}
