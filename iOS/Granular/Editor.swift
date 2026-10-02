import GranularCore
import Photos
import PhotosUI
import SwiftUI

/// The phone's Edit mode: one photo, previewed live with the loaded recipe
/// as it's adjusted, then developed at full size into Photos.
@MainActor
@Observable
final class Editor {
    enum SaveState: Equatable {
        case idle
        case saving
        case saved
    }

    private(set) var sourceURL: URL?
    /// The photo as it came, upright, for holding to compare.
    private(set) var original: CGImage?
    private(set) var preview: CGImage?
    private(set) var isLoadingPhoto = false
    private(set) var saveState = SaveState.idle
    private(set) var stockThumbnails: [FilmStockID: CGImage] = [:]
    var showsOriginal = false
    var failure: EditorFailure?

    private let darkroom: Darkroom
    /// Its own renderer, so previews never wait behind an Instant roll.
    @ObservationIgnored private lazy var service = try? ImageProcessingService()
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var refinementTask: Task<Void, Never>?
    @ObservationIgnored private var stockTask: Task<Void, Never>?
    @ObservationIgnored private var stockKey: StockThumbnailKey?
    @ObservationIgnored private var needsRender = false
    @ObservationIgnored private var wantsRefinement = false
    @ObservationIgnored private var renderedDimension: CGFloat = 0
    @ObservationIgnored private var displayDimension: CGFloat = 1_536
    @ObservationIgnored private var sourceLongEdge: Double?

    /// While a slider moves, previews render no larger than this, so they
    /// keep up; a sharper one follows when it rests.
    private static let interactiveDimension: CGFloat = 1_024
    private static let stockThumbnailSize = 180
    private static let photoKey = "editing.photo"

    /// The photo being edited is kept until another is chosen, so it's still
    /// there after the app has been away.
    private static var workspace: URL {
        URL.applicationSupportDirectory.appending(path: "Editing", directoryHint: .isDirectory)
    }

    init(darkroom: Darkroom) {
        self.darkroom = darkroom
        if let name = UserDefaults.standard.string(forKey: Self.photoKey) {
            let url = Self.workspace.appending(path: name)
            if FileManager.default.fileExists(atPath: url.path) {
                show(url)
            }
        }
    }

    // MARK: Choosing a photo

    func open(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            guard let picked = try await item.loadTransferable(type: PickedPhoto.self) else {
                throw DarkroomError.photoUnavailable
            }
            let folder = Self.workspace
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: picked.url.lastPathComponent)
            try FileManager.default.moveItem(at: picked.url, to: url)
            try? FileManager.default.removeItem(at: picked.url.deletingLastPathComponent())
            UserDefaults.standard.set(url.lastPathComponent, forKey: Self.photoKey)
            show(url)
        } catch {
            failure = .open(error.localizedDescription)
        }
    }

    private func show(_ url: URL) {
        cancelRendering()
        sourceURL = url
        sourceLongEdge = Self.longEdge(of: url)
        preview = nil
        original = nil
        saveState = .idle
        Task {
            let image = await Darkroom.thumbnail(of: url, maxPixelSize: Int(displayDimension))
            guard sourceURL == url else { return }
            original = image
        }
        schedulePreview()
        refreshStockThumbnails()
    }

    // MARK: Previews

    /// One render at a time; changes made while it runs are picked up as soon
    /// as it finishes, so a dragged slider never queues up stale renders.
    func schedulePreview() {
        guard sourceURL != nil else { return }
        refinementTask?.cancel()
        refinementTask = nil
        needsRender = true
        guard previewTask == nil else { return }
        previewTask = Task { await renderPendingPreviews() }
    }

    /// How large the preview is shown, as its long edge in pixels.
    func setDisplaySize(longEdge: CGFloat) {
        let dimension = CGFloat(PreviewSizing.renderDimension(
            displayedLongEdge: Double(longEdge),
            sourceLongEdge: sourceLongEdge
        ))
        guard dimension != displayDimension else { return }
        displayDimension = dimension
        if previewTask == nil {
            scheduleSharperPreview()
        }
    }

    private func renderPendingPreviews() async {
        while !Task.isCancelled, let sourceURL, let service {
            let dimension: CGFloat
            if needsRender {
                needsRender = false
                dimension = CGFloat(PreviewSizing.interactiveDimension(
                    for: Double(displayDimension),
                    limit: Double(Self.interactiveDimension)
                ))
            } else if wantsRefinement {
                wantsRefinement = false
                guard PreviewSizing.needsSharperRender(
                    rendered: Double(renderedDimension),
                    wanted: Double(displayDimension)
                ) else { continue }
                dimension = displayDimension
            } else {
                break
            }

            do {
                let image = try await service.renderPreview(
                    sourceURL: sourceURL,
                    recipe: darkroom.recipe,
                    maximumDimension: dimension
                )
                guard !Task.isCancelled else { return }
                preview = image
                renderedDimension = dimension
            } catch {
                guard !Task.isCancelled else { return }
                failure = .open(error.localizedDescription)
                break
            }
        }
        guard !Task.isCancelled else { return }
        previewTask = nil
        scheduleSharperPreview()
    }

    private func scheduleSharperPreview() {
        refinementTask?.cancel()
        refinementTask = nil
        guard PreviewSizing.needsSharperRender(
            rendered: Double(renderedDimension),
            wanted: Double(displayDimension)
        ) else { return }
        refinementTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            refinementTask = nil
            wantsRefinement = true
            guard previewTask == nil else { return }
            previewTask = Task { await renderPendingPreviews() }
        }
    }

    private func cancelRendering() {
        previewTask?.cancel()
        previewTask = nil
        refinementTask?.cancel()
        refinementTask = nil
        needsRender = false
        wantsRefinement = false
        renderedDimension = 0
    }

    // MARK: Film stocks

    /// Every stock's Film Tone on the photo, or on a color swatch without one.
    /// Tiles already showing stay until their replacements arrive.
    func refreshStockThumbnails() {
        guard let service else { return }
        var tone = darkroom.recipe.tone
        tone.isEnabled = true
        tone.stock = .none
        let key = StockThumbnailKey(sourceURL: sourceURL, tone: tone)
        guard key != stockKey else { return }
        if stockKey?.sourceURL != key.sourceURL {
            stockThumbnails = [:]
        }
        let isRefresh = !stockThumbnails.isEmpty
        stockKey = key
        stockTask?.cancel()
        stockTask = Task {
            if isRefresh {
                try? await Task.sleep(for: .milliseconds(200))
            }
            for stock in FilmStockID.allCases {
                guard !Task.isCancelled else { return }
                guard let image = try? await service.renderStockThumbnail(
                    sourceURL: key.sourceURL,
                    tone: tone,
                    stock: stock,
                    maximumPixelSize: Self.stockThumbnailSize
                ), !Task.isCancelled else { continue }
                stockThumbnails[stock] = image
            }
        }
    }

    // MARK: Saving

    /// Develops the photo at full size and adds it to the library. It's an
    /// exposure like any other, so it counts on the film back.
    func save() async {
        guard let sourceURL, let service, saveState != .saving else { return }
        saveState = .saving
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Edited-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                saveState = .idle
                failure = .photosAccess
                return
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let output = try await service.process(
                sourceURL: sourceURL,
                destinationFolder: folder,
                recipe: darkroom.recipe,
                options: OutputOptions()
            )
            try await Darkroom.addToLibrary(output)
            darkroom.recordExposure()
            darkroom.persistRecipe()
            saveState = .saved
            try? await Task.sleep(for: .seconds(1.8))
            if saveState == .saved {
                saveState = .idle
            }
        } catch {
            saveState = .idle
            failure = .save(error.localizedDescription)
        }
    }

    private static func longEdge(of url: URL) -> Double? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double else { return nil }
        return max(width, height)
    }
}

private struct StockThumbnailKey: Equatable {
    let sourceURL: URL?
    let tone: FilmToneSettings
}

enum EditorFailure: Identifiable, Equatable {
    case open(String)
    case save(String)
    case photosAccess

    var id: String { title + message }

    var title: String {
        switch self {
        case .open: "Couldn’t Open Photo"
        case .save: "Couldn’t Save Photo"
        case .photosAccess: "Granular Can’t Add to Photos"
        }
    }

    var message: String {
        switch self {
        case .open(let reason), .save(let reason): reason
        case .photosAccess: "Allow Granular to add photos in Settings."
        }
    }
}
