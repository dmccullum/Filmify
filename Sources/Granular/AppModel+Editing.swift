import AppKit
import GranularCore
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// Edit mode: opening, previewing and exporting a single image.
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
        panel.title = "Open Image"
        panel.allowedContentTypes = Self.supportedImageTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        openForEditing(panel.urls)
    }

    func openForEditing(_ urls: [URL]) {
        guard let url = urls.first(where: Self.isSupportedImage) else {
            statusMessage = "Choose a JPEG, HEIC, PNG, or TIFF image"
            return
        }
        guard let image = NSImage(contentsOf: url) else {
            statusMessage = "Couldn’t open \(url.lastPathComponent)"
            return
        }

        retainSecurityScope(for: url)
        previewTask?.cancel()
        previewTask = nil
        selectedSourceURL = url
        sourcePreview = image
        processedPreview = nil
        showOriginal = false
        operationMode = .edit
        statusMessage = "Rendering preview…"
        scheduleWindowResize(for: .edit, animated: true)
        schedulePreview()
    }

    func closeEditorImage() {
        previewTask?.cancel()
        previewTask = nil
        selectedSourceURL = nil
        sourcePreview = nil
        processedPreview = nil
        showOriginal = false
        isRenderingPreview = false
        statusMessage = "Ready"
    }

    func exportEditedImage() {
        guard let sourceURL = selectedSourceURL else { return }
        let type = resolvedOutputType(for: sourceURL)
        let panel = NSSavePanel()
        panel.title = "Export Filmified Image"
        panel.prompt = "Export"
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedExportName(for: sourceURL, type: type)
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
        } catch {
            updateJob(job.id, state: .failed(error.localizedDescription))
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

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
            do {
                let image = try await processingService.renderPreview(
                    sourceURL: sourceURL,
                    recipe: recipe,
                    maximumDimension: 2_400
                )
                guard !Task.isCancelled else { return }
                processedPreview = NSImage(cgImage: image, size: .zero)
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

    func resolvedOutputType(for sourceURL: URL) -> UTType {
        switch outputOptions.format {
        case .jpeg: .jpeg
        case .heic: .heic
        case .png: .png
        case .tiff: .tiff
        case .sameAsSource:
            switch sourceURL.pathExtension.lowercased() {
            case "jpg", "jpeg": .jpeg
            case "heic", "heif": .heic
            case "png": .png
            default: .tiff
            }
        }
    }
}
