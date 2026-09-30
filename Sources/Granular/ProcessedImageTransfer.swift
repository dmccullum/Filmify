import AppKit
import CoreTransferable
import GranularCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Handing the processed image to other apps: sharing, dragging and copying.
// Each renders the full-resolution image on demand into a temporary file
// that carries the same name an export would.
extension AppModel {
    /// Renders the open image, or another open one, at full resolution with
    /// the current recipe and export settings.
    func renderProcessedImageForTransfer(_ sourceURL: URL? = nil) async throws -> URL {
        guard let processingService, let sourceURL = sourceURL ?? selectedSourceURL else {
            throw ImageExporterError.imageCreationFailed
        }
        transferRenderCount += 1
        defer { transferRenderCount -= 1 }
        let destination = try TransferFiles.makeDestination(named: exportFileName(for: sourceURL))
        return try await processingService.process(
            sourceURL: sourceURL,
            destinationURL: destination,
            recipe: recipe,
            options: outputOptions
        )
    }

    /// Puts the processed image on the pasteboard as image data, with its
    /// file for apps that would rather take a file.
    func copyProcessedImage() {
        guard selectedSourceURL != nil else { return }
        Task {
            do {
                let file = try await renderProcessedImageForTransfer()
                let tiff = try await Task.detached(priority: .userInitiated) {
                    try TransferFiles.tiffData(forImageAt: file)
                }.value
                let item = NSPasteboardItem()
                item.setData(tiff, forType: .tiff)
                item.setString(file.absoluteString, forType: .fileURL)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([item])
                showEditorNotice("Copied “\(file.lastPathComponent)”")
            } catch {
                editorAlert = EditorAlert(
                    title: "The image couldn’t be copied.",
                    message: error.localizedDescription
                )
            }
        }
    }

    func processedImageItem(for sourceURL: URL) -> ProcessedImageItem {
        ProcessedImageItem(sourceURL: sourceURL, contentType: resolvedOutputType(for: sourceURL), model: self)
    }
}

/// The processed image as something to share. Nothing renders until a
/// service asks for the file.
struct ProcessedImageItem: Transferable {
    let sourceURL: URL
    let contentType: UTType
    let model: AppModel

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .jpeg, exporting: { try await $0.renderedFile() })
            .exportingCondition { $0.contentType == .jpeg }
        FileRepresentation(exportedContentType: .heic, exporting: { try await $0.renderedFile() })
            .exportingCondition { $0.contentType == .heic }
        FileRepresentation(exportedContentType: .png, exporting: { try await $0.renderedFile() })
            .exportingCondition { $0.contentType == .png }
        FileRepresentation(exportedContentType: .tiff, exporting: { try await $0.renderedFile() })
            .exportingCondition { $0.contentType == .tiff }
    }

    private func renderedFile() async throws -> SentTransferredFile {
        SentTransferredFile(try await model.renderProcessedImageForTransfer(sourceURL))
    }
}

/// Temporary renders for sharing, dragging and copying. Each lives in its own
/// folder so it can keep the export name; all are removed at launch and quit.
enum TransferFiles {
    private static var root: URL {
        FileManager.default.temporaryDirectory.appending(path: "Granular Transfers", directoryHint: .isDirectory)
    }

    static func makeDestination(named name: String) throws -> URL {
        let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: name)
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    /// TIFF data for the pasteboard, LZW-compressed to keep it a sensible size.
    static func tiffData(forImageAt url: URL) throws -> Data {
        if UTType(filenameExtension: url.pathExtension) == .tiff {
            return try Data(contentsOf: url)
        }
        let data = NSMutableData()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let destination = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil)
        else {
            throw ImageExporterError.destinationCreationFailed
        }
        let properties = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]]
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageExporterError.finalizeFailed }
        return data as Data
    }
}

// MARK: Dragging out

extension View {
    /// Lets the processed image be dragged out to the Finder, Mail or any app
    /// that takes files. While `isEnabled` is false the view’s own drags win,
    /// so a zoomed image still pans.
    func processedImageDragSource(isEnabled: Bool) -> some View {
        modifier(ProcessedImageDragSource(isEnabled: isEnabled))
    }
}

private struct ProcessedImageDragSource: ViewModifier {
    @Environment(AppModel.self) private var model
    let isEnabled: Bool
    @State private var dragSource = ProcessedImageDraggingSource()

    func body(content: Content) -> some View {
        content.highPriorityGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    guard let sourceURL = model.selectedSourceURL else { return }
                    dragSource.beginIfNeeded(
                        fileName: model.exportFileName(for: sourceURL),
                        fileType: model.resolvedOutputType(for: sourceURL),
                        dragImage: model.processedPreview ?? model.sourcePreview
                    ) { [model] in
                        try await model.renderProcessedImageForTransfer(sourceURL)
                    }
                },
            including: isEnabled ? .all : .subviews
        )
    }
}

/// Starts an AppKit drag of a file promise, so the full-size render happens
/// only once the image lands, straight into the place it was dropped.
@MainActor
private final class ProcessedImageDraggingSource: NSObject, NSDraggingSource {
    private var isDragging = false

    func beginIfNeeded(
        fileName: String,
        fileType: UTType,
        dragImage: NSImage?,
        render: @escaping @Sendable @MainActor () async throws -> URL
    ) {
        guard !isDragging,
              let event = NSApp.currentEvent, event.type == .leftMouseDragged,
              let view = event.window?.contentView else { return }
        isDragging = true

        let promise = ProcessedImagePromise(fileName: fileName, render: render)
        let provider = NSFilePromiseProvider(fileType: fileType.identifier, delegate: promise)
        provider.userInfo = promise

        let item = NSDraggingItem(pasteboardWriter: provider)
        let image = dragImage ?? NSWorkspace.shared.icon(for: fileType)
        let size = Self.dragImageSize(for: image.size)
        let location = view.convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(
                x: location.x - size.width / 2,
                y: location.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            contents: image
        )
        view.beginDraggingSession(with: [item], event: event, source: self)
    }

    private static func dragImageSize(for size: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0 else { return NSSize(width: 128, height: 128) }
        let scale = 180 / max(size.width, size.height)
        return NSSize(width: size.width * scale, height: size.height * scale)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
    }
}

/// Writes the promised file: renders to a temporary file, then copies it to
/// exactly the place the receiving app asked for.
private final class ProcessedImagePromise: NSObject, NSFilePromiseProviderDelegate, Sendable {
    private let fileName: String
    private let render: @Sendable @MainActor () async throws -> URL

    init(fileName: String, render: @escaping @Sendable @MainActor () async throws -> URL) {
        self.fileName = fileName
        self.render = render
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        fileName
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let completion = UncheckedCompletion(handler: completionHandler)
        Task { [render] in
            do {
                let file = try await render()
                try FileManager.default.copyItem(at: file, to: url)
                completion.handler(nil)
            } catch {
                completion.handler(error)
            }
        }
    }
}

/// AppKit’s promise completion handler may be called from any thread.
private struct UncheckedCompletion: @unchecked Sendable {
    let handler: (Error?) -> Void
}
