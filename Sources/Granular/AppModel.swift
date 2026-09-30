import AppKit
import GranularCore
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum OperationMode: String, CaseIterable, Identifiable {
    case drop = "Instant"
    case edit = "Edit"

    var id: String { rawValue }
}

enum EffectCenterTarget: String, Equatable {
    case vignette
    case lensBlur

    var title: String {
        switch self {
        case .vignette: "Vignette"
        case .lensBlur: "Lens Blur"
        }
    }

    var symbol: String {
        switch self {
        case .vignette: "camera.aperture"
        case .lensBlur: "drop.halffull"
        }
    }
}

enum JobState: Equatable {
    case queued
    case processing
    case finished(URL)
    case failed(String)

    var label: String {
        switch self {
        case .queued: "Queued"
        case .processing: "Processing"
        case .finished: "Finished"
        case .failed: "Needs Attention"
        }
    }
}

struct StockThumbnailKey: Equatable {
    let sourceURL: URL?
    let tone: FilmToneSettings
}

struct ProcessingJob: Identifiable {
    let id = UUID()
    let sourceURL: URL
    var state: JobState
}

@MainActor
@Observable
final class AppModel {
    var operationMode: OperationMode = .drop {
        didSet {
            // Start the transition in the same update as the switch, so each
            // mode is laid out at its own size from the very first frame.
            if operationMode != oldValue {
                isSettlingWindow = true
                arrivingLayoutSize = layoutSize(for: operationMode)
            }
            if operationMode != .drop {
                isFilmLoaded = false
            }
        }
    }
    /// Whether film is loaded in Instant mode's camera back. It loads as the
    /// window settles into Instant mode and rewinds as it leaves.
    var isFilmLoaded = false
    /// While switching modes, the size the arriving mode's content will have
    /// once the window arrives, so it can be laid out there from the start.
    var arrivingLayoutSize: CGSize?

    /// One duration and curve for everything in a mode switch: the window,
    /// the crossfade and the film, so it reads as a single motion.
    static let modeTransitionDuration = 0.42
    static let modeTransitionCurve = (x1: 0.32, y1: 0.72, x2: 0.0, y2: 1.0)
    static var modeTransitionAnimation: Animation {
        let c = modeTransitionCurve
        return .timingCurve(c.x1, c.y1, c.x2, c.y2, duration: modeTransitionDuration)
    }
    var recipe: FilmRecipe = .classic35
    var selectedRecipeID = FilmRecipe.classic35.id
    var savedRecipes: [FilmRecipe] = []
    var showRecipeManager = false
    var isSavingRecipe = false
    var showOriginal = false
    var activeCenterTarget: EffectCenterTarget?
    var isDropTargeted = false
    /// True while the window resizes between modes. The camera body stays up
    /// with the film unloaded until the window has reached its final size.
    var isSettlingWindow = false
    var outputOptions = OutputOptions()

    var dropOutputFolder: URL?
    var watchedInputFolder: URL?
    var watchedOutputFolder: URL?
    var isWatching = false
    var showMenuBarExtra = false

    var sourcePreview: NSImage?
    var processedPreview: NSImage?
    var stockThumbnails: [FilmStockID: NSImage] = [:]
    var selectedSourceURL: URL?
    var isRenderingPreview = false
    var isExporting = false
    var jobs: [ProcessingJob] = []
    var statusMessage = "Ready"
    var watchStatusMessage = "Choose Incoming and Finished folders, then start watching."
    var watchErrorMessage: String?
    var startupError: String?

    var processingService: ImageProcessingService?
    var previewTask: Task<Void, Never>?
    var previewNeedsRender = false
    var stockThumbnailTask: Task<Void, Never>?
    var stockThumbnailKey: StockThumbnailKey?
    static let stockThumbnailPixelSize = 224
    var resizeTask: Task<Void, Never>?
    var monitor: WatchedFolderMonitor?
    var activeSecurityURLs: [URL] = []

    // MARK: Settings & window state
    // Keep each area's new stored state under its own mark.

    // MARK: Undo state
    // Keep each area's new stored state under its own mark.
    /// The main window's undo manager, where changes to the adjustments go.
    @ObservationIgnored weak var undoManager: UndoManager?
    /// The step a run of changes is joining, such as one slider drag.
    @ObservationIgnored var openUndoStep: OpenUndoStep?
    @ObservationIgnored var adjustmentChangeDepth = 0

    // MARK: Viewer state
    // Keep each area's new stored state under its own mark.

    // MARK: Edit document state
    // Keep each area's new stored state under its own mark.

    // MARK: Instant processing state
    // Keep each area's new stored state under its own mark.

    // MARK: Recipe library state
    // Keep each area's new stored state under its own mark.

    // MARK: System integration state
    // Keep each area's new stored state under its own mark.

    init() {
        do {
            processingService = try ImageProcessingService()
        } catch {
            startupError = error.localizedDescription
        }

        restoreRecipes()
        restoreRecipeSelection()
        restoreFolder(forKey: BookmarkKey.dropOutput) { dropOutputFolder = $0 }
        restoreFolder(forKey: BookmarkKey.watchInput) { watchedInputFolder = $0 }
        restoreFolder(forKey: BookmarkKey.watchOutput) { watchedOutputFolder = $0 }
    }

    var previewImage: NSImage? {
        if showOriginal { return sourcePreview }
        return processedPreview ?? sourcePreview
    }

    func centerPosition(for target: EffectCenterTarget) -> CGPoint {
        switch target {
        case .vignette:
            CGPoint(x: recipe.lightShaping.centerX, y: recipe.lightShaping.centerY)
        case .lensBlur:
            CGPoint(x: recipe.lensBlur.focusX, y: recipe.lensBlur.focusY)
        }
    }

    func updateCenter(for target: EffectCenterTarget, x: Double, y: Double) {
        let x = min(1, max(0, x))
        let y = min(1, max(0, y))

        // Each drag of the target is one step on Edit ▸ Undo.
        changeAdjustments("Move \(target.title) Center", coalescingKey: target) {
            switch target {
            case .vignette:
                recipe.lightShaping.centerX = x
                recipe.lightShaping.centerY = y
            case .lensBlur:
                recipe.lensBlur.focusX = x
                recipe.lensBlur.focusY = y
            }
        }
    }

    func finishCenterAdjustment() {
        activeCenterTarget = nil
        endCoalescedChanges()
    }

    var availableRecipes: [FilmRecipe] {
        FilmRecipe.builtIns + savedRecipes
    }

    var currentRecipe: FilmRecipe {
        availableRecipes.first { $0.id == selectedRecipeID } ?? .classic35
    }

    var isRecipeModified: Bool {
        recipe != currentRecipe
    }

    var recipeDisplayName: String {
        isRecipeModified ? "Custom" : currentRecipe.name
    }

    var isSelectedRecipeCustom: Bool {
        savedRecipes.contains { $0.id == selectedRecipeID }
    }

    var completedJobCount: Int {
        jobs.filter {
            if case .finished = $0.state { return true }
            return false
        }.count
    }

    var failedJobCount: Int {
        jobs.filter {
            if case .failed = $0.state { return true }
            return false
        }.count
    }

    var lastFinishedURL: URL? {
        jobs.compactMap { job -> URL? in
            if case .finished(let url) = job.state { return url }
            return nil
        }.first
    }


    static let supportedImageTypes: [UTType] = [.jpeg, .heic, .png, .tiff]

    static func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return supportedImageTypes.contains(type)
    }

    static func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
