import AppKit
import GranularCore
import Foundation
import ImageIO
import Observation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// Edit mode: opening, previewing and exporting images, one recipe across all of them.
extension AppModel {
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
        panel.title = "Open Images"
        panel.allowedContentTypes = Self.supportedImageTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        openForEditing(panel.urls)
    }

    /// Opens images alongside any already open and shows the first of them.
    /// Files Granular can’t read are named in an alert rather than skipped silently.
    func openForEditing(_ urls: [URL]) {
        var readable: [URL] = []
        var unopened: [URL] = []
        for url in urls {
            guard Self.isSupportedImage(url) else {
                unopened.append(url)
                continue
            }
            retainSecurityScope(for: url)
            if Self.isReadableImage(url) {
                readable.append(url)
            } else {
                unopened.append(url)
            }
        }

        openImageURLs = OpenImages.appending(readable, to: openImageURLs)
        for url in readable {
            noteRecentImage(url)
            loadThumbnail(for: url)
        }
        if let first = readable.first,
           let shown = openImageURLs.first(where: { $0.standardizedFileURL == first.standardizedFileURL }) {
            showImage(shown)
        }
        if !unopened.isEmpty {
            editorAlert = .unopened(unopened, openedAny: !readable.isEmpty)
        }
    }

    /// Shows one of the open images in the canvas.
    func showImage(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            editorAlert = .unopened([url], openedAny: false)
            closeImage(url)
            return
        }

        previewTask?.cancel()
        previewTask = nil
        selectedSourceURL = url
        sourcePreview = image
        showOriginal = false
        let isChangingMode = operationMode != .edit
        operationMode = .edit
        if isChangingMode {
            scheduleWindowResize(for: .edit, animated: true)
        }

        if previewCacheRecipe == recipe, let cached = processedPreviewCache[url] {
            processedPreview = cached
            previewNeedsRender = false
            isRenderingPreview = false
            statusMessage = url.lastPathComponent
        } else {
            processedPreview = nil
            statusMessage = "Rendering preview…"
            schedulePreview()
        }
    }

    var canShowNextImage: Bool {
        OpenImages.neighbor(of: selectedSourceURL, offset: 1, in: openImageURLs) != nil
    }

    var canShowPreviousImage: Bool {
        OpenImages.neighbor(of: selectedSourceURL, offset: -1, in: openImageURLs) != nil
    }

    func showNextImage() {
        guard let url = OpenImages.neighbor(of: selectedSourceURL, offset: 1, in: openImageURLs) else { return }
        showImage(url)
    }

    func showPreviousImage() {
        guard let url = OpenImages.neighbor(of: selectedSourceURL, offset: -1, in: openImageURLs) else { return }
        showImage(url)
    }

    func closeEditorImage() {
        guard let url = selectedSourceURL else { return }
        closeImage(url)
    }

    /// Closes one image; if it was showing, its neighbour takes its place.
    func closeImage(_ url: URL) {
        let index = openImageURLs.firstIndex(of: url)
        openImageURLs.removeAll { $0 == url }
        imageThumbnails[url] = nil
        processedPreviewCache[url] = nil
        guard url == selectedSourceURL else { return }

        if let index, let next = OpenImages.selectionAfterClosing(at: index, remaining: openImageURLs) {
            showImage(next)
        } else {
            closeAllImages()
        }
    }

    func closeAllImages() {
        previewTask?.cancel()
        previewTask = nil
        openImageURLs = []
        imageThumbnails = [:]
        processedPreviewCache = [:]
        selectedSourceURL = nil
        sourcePreview = nil
        processedPreview = nil
        showOriginal = false
        isRenderingPreview = false
        statusMessage = "Ready"
    }

    /// A small thumbnail of the original for the filmstrip, read without
    /// decoding the whole image.
    func loadThumbnail(for url: URL) {
        guard imageThumbnails[url] == nil else { return }
        Task {
            let thumbnail = await Task.detached(priority: .utility) {
                Self.thumbnail(of: url, maximumPixelSize: 160)
            }.value
            guard let thumbnail, openImageURLs.contains(url) else { return }
            imageThumbnails[url] = NSImage(cgImage: thumbnail, size: .zero)
        }
    }

    nonisolated static func thumbnail(of url: URL, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary)
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
        isRenderingPreview = true
        previewNeedsRender = true
        guard previewTask == nil else { return }
        previewTask = Task { await renderPendingPreviews() }
    }

    func renderPendingPreviews() async {
        while previewNeedsRender, !Task.isCancelled,
              let sourceURL = selectedSourceURL, let processingService {
            previewNeedsRender = false
            let renderedRecipe = recipe
            do {
                let image = try await processingService.renderPreview(
                    sourceURL: sourceURL,
                    recipe: renderedRecipe,
                    maximumDimension: 2_400
                )
                guard !Task.isCancelled else { return }
                let preview = NSImage(cgImage: image, size: .zero)
                processedPreview = preview
                cacheProcessedPreview(preview, for: sourceURL, recipe: renderedRecipe)
                statusMessage = sourceURL.lastPathComponent
            } catch {
                guard !Task.isCancelled else { return }
                statusMessage = "Preview failed: \(error.localizedDescription)"
            }
        }
        guard !Task.isCancelled else { return }
        isRenderingPreview = false
        previewTask = nil
    }

    /// Keeps a few recent previews for the current recipe; any change to the
    /// recipe starts the cache afresh.
    private func cacheProcessedPreview(_ preview: NSImage, for url: URL, recipe: FilmRecipe) {
        if previewCacheRecipe != recipe {
            previewCacheRecipe = recipe
            processedPreviewCache = [:]
        }
        if processedPreviewCache.count >= 8,
           let evicted = processedPreviewCache.keys.first(where: { $0 != url }) {
            processedPreviewCache[evicted] = nil
        }
        processedPreviewCache[url] = preview
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
            showEditorNotice("Exported “\(output.lastPathComponent)”", revealing: output)
        } catch {
            updateJob(job.id, state: .failed(error.localizedDescription))
            statusMessage = "Export failed: \(error.localizedDescription)"
            editorAlert = .exportFailed([sourceURL], reason: error.localizedDescription)
        }
    }

    /// Exports every open image with the current recipe into one folder,
    /// named as Instant mode names its output.
    func exportAllImages() {
        guard !openImageURLs.isEmpty, batchExport == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Export All Images"
        panel.message = "Choose a folder for \(openImageURLs.count) filmified images."
        panel.prompt = "Export"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let urls = openImageURLs
        batchExport = BatchExportProgress(completed: 0, total: urls.count)
        batchExportTask = Task { await exportImages(urls, to: folder) }
    }

    func cancelBatchExport() {
        batchExportTask?.cancel()
    }

    private func exportImages(_ urls: [URL], to folder: URL) async {
        guard let processingService else { return }
        persistRecipeSelection()
        let recipe = recipe
        let options = outputOptions
        var failed: [URL] = []
        var lastError: String?
        var exported = 0

        for url in urls {
            guard !Task.isCancelled else { break }
            let job = ProcessingJob(sourceURL: url, state: .processing)
            jobs.insert(job, at: 0)
            statusMessage = "Exporting \(url.lastPathComponent)…"
            do {
                let output = try await processingService.process(
                    sourceURL: url,
                    destinationFolder: folder,
                    recipe: recipe,
                    options: options
                )
                updateJob(job.id, state: .finished(output))
                exported += 1
            } catch {
                updateJob(job.id, state: .failed(error.localizedDescription))
                failed.append(url)
                lastError = error.localizedDescription
            }
            batchExport?.completed += 1
        }

        batchExport = nil
        batchExportTask = nil
        statusMessage = "Exported \(exported) of \(urls.count) images"
        if !failed.isEmpty {
            editorAlert = .exportFailed(failed, reason: lastError)
        } else if exported > 0 {
            let noun = exported == 1 ? "image" : "images"
            showEditorNotice("Exported \(exported) \(noun) to “\(folder.lastPathComponent)”", revealing: folder)
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
    func showEditorNotice(_ message: String, revealing url: URL? = nil) {
        editorNoticeTask?.cancel()
        editorNotice = EditorNotice(message: message, revealURL: url)
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
    var editorWindowSubtitle: String {
        guard operationMode == .edit, selectedSourceURL != nil else { return "" }
        guard isRecipeModified else { return recipeDisplayName }
        return "\(currentRecipe.name) · \(recipeDisplayName)"
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
    @MainActor static func unopened(_ urls: [URL], openedAny: Bool) -> EditorAlert {
        let formats = "Granular opens JPEG, HEIC, PNG, TIFF, WebP, and AVIF images."
        if urls.count == 1, let url = urls.first {
            let reason = AppModel.isSupportedImage(url)
                ? "The file may be damaged, or saved in a form Granular can’t read."
                : formats
            return EditorAlert(title: "Granular can’t open “\(url.lastPathComponent)”.", message: reason)
        }
        let title = openedAny
            ? "\(urls.count) files weren’t opened."
            : "Granular can’t open these \(urls.count) files."
        return EditorAlert(title: title, message: "\(listing(urls))\n\n\(formats)")
    }

    static func missing(_ url: URL) -> EditorAlert {
        EditorAlert(
            title: "“\(url.lastPathComponent)” can’t be found.",
            message: "It may have been moved, renamed, or deleted."
        )
    }

    static func exportFailed(_ urls: [URL], reason: String?) -> EditorAlert {
        let title = urls.count == 1
            ? "“\(urls[0].lastPathComponent)” couldn’t be exported."
            : "\(urls.count) images couldn’t be exported."
        let detail = urls.count == 1 ? nil : listing(urls)
        return EditorAlert(
            title: title,
            message: [detail, reason].compactMap { $0 }.joined(separator: "\n\n")
        )
    }

    private static func listing(_ urls: [URL]) -> String {
        let names = urls.prefix(5).map(\.lastPathComponent)
        let more = urls.count > 5 ? ["and \(urls.count - 5) more"] : []
        return (names + more).joined(separator: "\n")
    }
}

struct EditorNotice: Equatable {
    let message: String
    let revealURL: URL?
}

struct BatchExportProgress: Equatable {
    var completed: Int
    let total: Int
}
