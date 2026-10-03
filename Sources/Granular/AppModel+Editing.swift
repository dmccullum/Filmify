import AppKit
import GranularCore
import Foundation
import ImageIO
import Observation
import SwiftUI
import UniformTypeIdentifiers

// Edit mode: one image at a time, previewed live with the recipe, then exported.
extension AppModel {
    /// Previews render at most this large while the recipe is changing, so a
    /// slider keeps up; a sharper one follows once it settles, if the viewer
    /// shows the image larger than this.
    static let interactivePreviewDimension: CGFloat = 2_400

    func chooseImages() {
        switch operationMode {
        case .drop:
            chooseImagesForDroplet()
        case .edit:
            chooseImageForEditing()
        }
    }

    func chooseImagesForDroplet() {
        let panel = NSOpenPanel()
        panel.title = "Choose Images to Process"
        panel.allowedContentTypes = Self.supportedImageTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        Task { await processInstantly(panel.urls) }
    }

    func chooseImageForEditing() {
        let panel = NSOpenPanel()
        panel.title = "Open Image"
        panel.allowedContentTypes = Self.supportedImageTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        openForEditing(panel.urls)
    }

    /// Opens the first of `urls` that Granular can read, in place of the image
    /// already open. Edit mode works on one image at a time, so when several
    /// arrive together the notice offers to process them all in Instant mode.
    /// If none can be opened, an alert names them rather than skipping silently.
    func openForEditing(_ urls: [URL]) {
        var unopened: [URL] = []
        var opened: URL?
        for url in urls {
            guard Self.isSupportedImage(url) else {
                unopened.append(url)
                continue
            }
            retainSecurityScope(for: url)
            if Self.isReadableImage(url), showImage(url) {
                opened = url
                break
            }
            unopened.append(url)
        }

        guard let opened else {
            if !unopened.isEmpty {
                editorAlert = .unopened(unopened)
            }
            return
        }
        noteRecentImage(opened)

        let images = urls.filter(Self.isSupportedImage)
        if images.count > 1 {
            showEditorNotice(
                "Opened “\(opened.lastPathComponent)”. Edit works on one image at a time.",
                action: .processInInstant(images)
            )
        }
    }

    /// Shows an image in the canvas, in place of any already open.
    private func showImage(_ url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url) else { return false }

        cancelPreviewRendering()
        selectedSourceURL = url
        sourcePreview = image
        sourceInfo = EditorSourceInfo(url: url)
        processedPreview = nil
        showOriginal = false
        editorNotice = nil
        let isChangingMode = operationMode != .edit
        operationMode = .edit
        if isChangingMode {
            scheduleWindowResize(for: .edit, animated: true)
        }
        statusMessage = "Rendering preview…"
        schedulePreview()
        return true
    }

    func closeEditorImage() {
        cancelPreviewRendering()
        selectedSourceURL = nil
        sourcePreview = nil
        sourceInfo = nil
        processedPreview = nil
        showOriginal = false
        isRenderingPreview = false
        statusMessage = "Ready"
    }

    /// Sends images that arrived in Edit mode over to Instant mode to be processed.
    func processInInstant(_ urls: [URL]) {
        editorNotice = nil
        operationMode = .drop
        Task { await processInstantly(urls) }
    }

    /// Whether ImageIO recognises the file as an image, read from its header.
    static func isReadableImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
    }

    // MARK: Recent images

    func noteRecentImage(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope) else { return }
        recentImages = OpenImages.recents(
            recentImages,
            adding: RecentImage(url: url, bookmark: bookmark),
            limit: RecentImageStore.limit
        ) { $0.url.standardizedFileURL == $1.url.standardizedFileURL }
        RecentImageStore.save(recentImages)
    }

    func openRecentImage(_ recent: RecentImage) {
        guard FileManager.default.fileExists(atPath: recent.url.path) else {
            editorAlert = .missing(recent.url)
            recentImages.removeAll { $0 == recent }
            RecentImageStore.save(recentImages)
            return
        }
        openForEditing([recent.url])
    }

    func clearRecentImages() {
        recentImages = []
        RecentImageStore.save([])
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    // MARK: Previews

    /// Renders the preview live: one render at a time, and any changes made
    /// while it runs are picked up as soon as it finishes, so dragging a
    /// slider never queues up stale renders.
    func schedulePreview() {
        guard operationMode == .edit, selectedSourceURL != nil, processingService != nil else {
            return
        }
        previewRefinementTask?.cancel()
        previewRefinementTask = nil
        updatePreviewDisplayDimension()
        // Setting an observed value tells its views even when it’s unchanged,
        // and this runs with every step of a slider drag.
        if !isRenderingPreview {
            isRenderingPreview = true
        }
        previewNeedsRender = true
        startRenderingPreviews()
    }

    /// Tells the preview how large the viewer shows the image, as its long
    /// edge in screen pixels. Previews render no larger than that; zooming in
    /// past the preview on screen renders a sharper one once the zoom
    /// settles, and panning never renders at all.
    func setPreviewDisplaySize(longEdge: CGFloat) {
        previewDisplayedLongEdge = longEdge
        if updatePreviewDisplayDimension(), previewTask == nil {
            scheduleSharperPreview()
        }
    }

    /// Grain is made on the preview's own pixels, so its preview is rendered at
    /// exactly the size it's shown. A larger one shrunk to fit softens the
    /// grain by an amount that changes with every zoom level.
    private var previewShowsGrain: Bool {
        recipe.grain.isEnabled && recipe.grain.amount != 0
    }

    @discardableResult
    private func updatePreviewDisplayDimension() -> Bool {
        let dimension = CGFloat(PreviewSizing.renderDimension(
            displayedLongEdge: Double(previewDisplayedLongEdge),
            sourceLongEdge: sourceInfo.map { Double($0.longEdge) },
            exact: previewShowsGrain
        ))
        guard dimension != previewDisplayDimension else { return false }
        previewDisplayDimension = dimension
        return true
    }

    private func startRenderingPreviews() {
        guard previewTask == nil else { return }
        previewTask = Task { await renderPendingPreviews() }
    }

    private func cancelPreviewRendering() {
        previewTask?.cancel()
        previewTask = nil
        previewRefinementTask?.cancel()
        previewRefinementTask = nil
        previewNeedsRender = false
        previewWantsRefinement = false
        renderedPreviewDimension = 0
    }

    private func renderPendingPreviews() async {
        while !Task.isCancelled, let sourceURL = selectedSourceURL, let processingService {
            let dimension: CGFloat
            if previewNeedsRender {
                previewNeedsRender = false
                dimension = CGFloat(PreviewSizing.interactiveDimension(
                    for: Double(previewDisplayDimension),
                    limit: Double(Self.interactivePreviewDimension)
                ))
            } else if previewWantsRefinement {
                previewWantsRefinement = false
                guard PreviewSizing.needsSharperRender(
                    rendered: Double(renderedPreviewDimension),
                    wanted: Double(previewDisplayDimension),
                    exact: previewShowsGrain
                ) else { continue }
                dimension = previewDisplayDimension
            } else {
                break
            }

            do {
                let image = try await processingService.renderPreview(
                    sourceURL: sourceURL,
                    recipe: recipe,
                    maximumDimension: dimension,
                    grainDimension: previewShowsGrain ? previewDisplayDimension : nil
                )
                guard !Task.isCancelled else { return }
                processedPreview = NSImage(cgImage: image, size: .zero)
                renderedPreviewDimension = dimension
                statusMessage = sourceURL.lastPathComponent
            } catch {
                guard !Task.isCancelled else { return }
                statusMessage = "Preview failed: \(error.localizedDescription)"
            }
        }
        guard !Task.isCancelled else { return }
        isRenderingPreview = false
        previewTask = nil
        scheduleSharperPreview()
    }

    /// Once changes and zooming have settled, renders a sharper preview if
    /// the viewer shows the image larger than the one on screen.
    private func scheduleSharperPreview() {
        previewRefinementTask?.cancel()
        previewRefinementTask = nil
        guard operationMode == .edit, PreviewSizing.needsSharperRender(
            rendered: Double(renderedPreviewDimension),
            wanted: Double(previewDisplayDimension),
            exact: previewShowsGrain
        ) else { return }
        previewRefinementTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            previewRefinementTask = nil
            previewWantsRefinement = true
            startRenderingPreviews()
        }
    }

    /// Renders a small Film Tone preview of every stock for the stock picker,
    /// using the open image or a generated color swatch. Existing tiles
    /// stay visible until their replacements arrive, one stock at a time.
    func refreshStockThumbnails() {
        guard let processingService else { return }
        var tone = recipe.tone
        tone.isEnabled = true
        tone.stock = .none
        let key = StockThumbnailKey(sourceURL: selectedSourceURL, tone: tone)
        guard key != stockThumbnailKey else { return }

        if stockThumbnailKey?.sourceURL != key.sourceURL {
            stockThumbnails = [:]
        }
        let isRefresh = !stockThumbnails.isEmpty
        stockThumbnailKey = key
        stockThumbnailTask?.cancel()
        stockThumbnailTask = Task {
            if isRefresh {
                try? await Task.sleep(for: .milliseconds(150))
            }
            for stock in FilmStockID.allCases {
                guard !Task.isCancelled else { return }
                guard let image = try? await processingService.renderStockThumbnail(
                    sourceURL: key.sourceURL,
                    tone: tone,
                    stock: stock,
                    maximumPixelSize: Self.stockThumbnailPixelSize
                ), !Task.isCancelled else { continue }
                stockThumbnails[stock] = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    // MARK: Exporting

    func exportEditedImage() {
        guard let sourceURL = selectedSourceURL else { return }
        let type = resolvedOutputType(for: sourceURL)
        let panel = NSSavePanel()
        panel.title = "Export Filmified Image"
        panel.prompt = "Export"
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = exportFileName(for: sourceURL)
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        Task { await exportEditor(sourceURL: sourceURL, destinationURL: destinationURL) }
    }

    func exportEditor(sourceURL: URL, destinationURL: URL) async {
        guard let processingService else { return }
        persistRecipeSelection()
        let job = ProcessingJob(sourceURL: sourceURL, state: .processing)
        jobs.insert(job, at: 0)
        isExporting = true
        statusMessage = "Exporting \(destinationURL.lastPathComponent)…"
        defer { isExporting = false }

        do {
            let output = try await processingService.process(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                recipe: recipe,
                options: outputOptions
            )
            updateJob(job.id, state: .finished(output))
            statusMessage = "Exported \(output.lastPathComponent)"
            showEditorNotice("Exported “\(output.lastPathComponent)”", action: .reveal(output))
        } catch {
            updateJob(job.id, state: .failed(error.localizedDescription))
            statusMessage = "Export failed: \(error.localizedDescription)"
            editorAlert = .exportFailed(sourceURL, reason: error.localizedDescription)
        }
    }

    /// The export name from the filename template in Settings.
    func exportFileName(for sourceURL: URL) -> String {
        suggestedExportName(for: sourceURL, type: resolvedOutputType(for: sourceURL))
    }

    func resolvedOutputType(for sourceURL: URL) -> UTType {
        switch outputOptions.format {
        case .jpeg: .jpeg
        case .heic: .heic
        case .png: .png
        case .tiff: .tiff
        case .sameAsSource:
            switch sourceURL.pathExtension.lowercased() {
            case "jpg", "jpeg", "webp": .jpeg
            case "heic", "heif", "avif": .heic
            case "png": .png
            default: .tiff
            }
        }
    }

    /// A short confirmation in the status bar that clears itself.
    func showEditorNotice(_ message: String, action: EditorNotice.Action? = nil) {
        editorNoticeTask?.cancel()
        editorNotice = EditorNotice(message: message, action: action)
        editorNoticeTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            editorNotice = nil
        }
    }

    // MARK: Window

    var editorWindowTitle: String {
        guard operationMode == .edit, let url = selectedSourceURL else { return "Granular" }
        return url.lastPathComponent
    }

    /// The recipe shown under the file name, with “Custom” once it’s been adjusted.
    /// The recipe, then the original’s size, format and file size.
    var editorWindowSubtitle: String {
        guard operationMode == .edit, selectedSourceURL != nil else { return "" }
        var parts = isRecipeModified ? [currentRecipe.name, recipeDisplayName] : [recipeDisplayName]
        if let sourceInfo {
            parts.append(sourceInfo.summary)
        }
        return parts.joined(separator: " · ")
    }
}

/// An image opened recently, with the bookmark that lets the sandbox reopen it.
struct RecentImage: Identifiable, Equatable {
    let url: URL
    let bookmark: Data

    var id: URL { url }
}

/// Recent images, kept as security-scoped bookmarks so they can be reopened
/// from the menu or the Dock after a relaunch.
enum RecentImageStore {
    static let limit = 10
    private static let key = "editor.recentImages"

    static func load() -> [RecentImage] {
        let bookmarks = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        return bookmarks.compactMap { bookmark in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), FileManager.default.fileExists(atPath: url.path) else { return nil }
            return RecentImage(url: url, bookmark: bookmark)
        }
    }

    static func save(_ recents: [RecentImage]) {
        UserDefaults.standard.set(recents.map(\.bookmark), forKey: key)
    }

    /// Menu titles, with the folder added where two recent files share a name.
    static func menuTitle(for recent: RecentImage, among recents: [RecentImage]) -> String {
        let name = recent.url.lastPathComponent
        let isAmbiguous = recents.contains { $0 != recent && $0.url.lastPathComponent == name }
        guard isAmbiguous else { return name }
        return "\(name) — \(recent.url.deletingLastPathComponent().lastPathComponent)"
    }
}

struct EditorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    /// Files that aren’t images Granular can read, named so it’s clear which.
    @MainActor static func unopened(_ urls: [URL]) -> EditorAlert {
        let formats = "Granular opens JPEG, HEIC, PNG, TIFF, WebP, and AVIF images."
        if urls.count == 1, let url = urls.first {
            let reason = AppModel.isSupportedImage(url)
                ? "The file may be damaged, or saved in a form Granular can’t read."
                : formats
            return EditorAlert(title: "Granular can’t open “\(url.lastPathComponent)”.", message: reason)
        }
        return EditorAlert(
            title: "Granular can’t open these \(urls.count) files.",
            message: "\(listing(urls))\n\n\(formats)"
        )
    }

    static func missing(_ url: URL) -> EditorAlert {
        EditorAlert(
            title: "“\(url.lastPathComponent)” can’t be found.",
            message: "It may have been moved, renamed, or deleted."
        )
    }

    static func exportFailed(_ url: URL, reason: String) -> EditorAlert {
        EditorAlert(title: "“\(url.lastPathComponent)” couldn’t be exported.", message: reason)
    }

    private static func listing(_ urls: [URL]) -> String {
        let names = urls.prefix(5).map(\.lastPathComponent)
        let more = urls.count > 5 ? ["and \(urls.count - 5) more"] : []
        return (names + more).joined(separator: "\n")
    }
}

struct EditorNotice: Equatable {
    enum Action: Equatable {
        /// Show in Finder.
        case reveal(URL)
        /// Process images that arrived in Edit mode with Instant mode instead.
        case processInInstant([URL])
    }

    let message: String
    let action: Action?
}

/// What the status bar says about the open image, read from its header.
struct EditorSourceInfo: Equatable {
    /// Upright, as it’s shown and exported.
    let pixelSize: CGSize
    /// The format, such as “JPEG”.
    let formatName: String?
    let byteCount: Int?

    /// “6000 × 4000 · JPEG · 12.4 MB”
    var summary: String {
        var parts = ["\(Int(pixelSize.width)) × \(Int(pixelSize.height))"]
        if let formatName {
            parts.append(formatName)
        }
        if let byteCount {
            parts.append(Int64(byteCount).formatted(.byteCount(style: .file)))
        }
        return parts.joined(separator: " · ")
    }

    var longEdge: CGFloat {
        max(pixelSize.width, pixelSize.height)
    }

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // Orientations 5 to 8 turn the image on its side.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        pixelSize = orientation >= 5
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
        formatName = CGImageSourceGetType(source)
            .flatMap { UTType($0 as String)?.preferredFilenameExtension?.uppercased() }
        byteCount = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }
}
