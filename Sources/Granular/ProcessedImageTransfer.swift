import AppKit
import CoreTransferable
import GranularCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Handing the processed image to other apps: sharing, dragging and copying.
// Each takes the full-size image rendered into a temporary file that carries
// the name an export would. The render starts the moment a share or drag
// begins, alongside the picker or the drag rather than before it, and is kept
// while the image and its settings stay the same, so doing it again is instant.

/// Everything a full-size render depends on.
struct TransferRenderKey: Equatable, Sendable {
    let sourceURL: URL
    let recipe: FilmRecipe
    let options: OutputOptions
    let fileName: String
    let contentType: UTType
}

/// A full-size render, finished or under way.
struct TransferRender {
    let key: TransferRenderKey
    let task: Task<URL, any Error>
}

extension AppModel {
    /// The open image as it would export now.
    var transferRenderKey: TransferRenderKey? {
        guard let sourceURL = selectedSourceURL else { return nil }
        return TransferRenderKey(
            sourceURL: sourceURL,
            recipe: recipe,
            options: outputOptions,
            fileName: exportFileName(for: sourceURL),
            contentType: resolvedOutputType(for: sourceURL)
        )
    }

    /// Starts rendering `key` in the background, or returns the render
    /// already made or under way for it.
    @discardableResult
    func prepareTransferRender(_ key: TransferRenderKey) -> Task<URL, any Error> {
        if let transferRender, transferRender.key == key {
            return transferRender.task
        }
        if let previous = transferRender {
            TransferFiles.remove(previous.task)
        }
        let processingService = processingService
        let task = Task<URL, any Error> {
            guard let processingService else { throw ImageExporterError.imageCreationFailed }
            let destination = try TransferFiles.makeDestination(named: key.fileName)
            return try await processingService.process(
                sourceURL: key.sourceURL,
                destinationURL: destination,
                recipe: key.recipe,
                options: key.options
            )
        }
        transferRender = TransferRender(key: key, task: task)
        return task
    }

    /// The rendered file for `key`, with progress in the status bar while it’s waited on.
    func renderProcessedImageForTransfer(_ key: TransferRenderKey) async throws -> URL {
        transferRenderCount += 1
        defer { transferRenderCount -= 1 }
        do {
            let file = try await prepareTransferRender(key).value
            if FileManager.default.fileExists(atPath: file.path) {
                return file
            }
            // Something has cleared the temporary folder since; render it again.
            forgetTransferRender(key)
            return try await prepareTransferRender(key).value
        } catch {
            forgetTransferRender(key)
            throw error
        }
    }

    /// The open image as it would export now, for File ▸ Share.
    func renderCurrentImageForTransfer() async throws -> URL {
        guard let key = transferRenderKey else { throw ImageExporterError.imageCreationFailed }
        return try await renderProcessedImageForTransfer(key)
    }

    private func forgetTransferRender(_ key: TransferRenderKey) {
        if transferRender?.key == key {
            transferRender = nil
        }
    }

    /// Puts the processed image on the pasteboard as image data, with its
    /// file for apps that would rather take a file.
    func copyProcessedImage() {
        guard let key = transferRenderKey else { return }
        Task {
            do {
                let file = try await renderProcessedImageForTransfer(key)
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

    /// Shows the share picker straight away, below `view`. The full-size
    /// render starts alongside it, and is handed over once a service asks
    /// for the file, so choosing one waits only for what’s left of it.
    func shareProcessedImage(from view: NSView) {
        guard let key = transferRenderKey else { return }
        prepareTransferRender(key)
        let picker = ProcessedImageSharePicker(key: key, preview: processedPreview, model: self)
        sharePicker = picker
        picker.show(relativeTo: view)
    }

    func processedImageItem(for sourceURL: URL) -> ProcessedImageItem {
        ProcessedImageItem(contentType: resolvedOutputType(for: sourceURL), model: self)
    }
}

/// The standard share picker, offering the processed image as a file that is
/// rendered, if it isn’t already, only once a service asks for it.
@MainActor
final class ProcessedImageSharePicker: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    private let picker: NSSharingServicePicker
    private weak var model: AppModel?

    init(key: TransferRenderKey, preview: NSImage?, model: AppModel) {
        let provider = NSItemProvider()
        provider.suggestedName = (key.fileName as NSString).deletingPathExtension
        provider.registerFileRepresentation(
            forTypeIdentifier: key.contentType.identifier,
            fileOptions: [],
            visibility: .all
        ) { [weak model] completion in
            let progress = Progress(totalUnitCount: 1)
            Task { @MainActor in
                defer { progress.completedUnitCount = 1 }
                do {
                    guard let model else { throw CocoaError(.userCancelled) }
                    completion(try await model.renderProcessedImageForTransfer(key), false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return progress
        }
        let item = NSPreviewRepresentingActivityItem(item: provider, title: key.fileName, image: preview, icon: nil)
        picker = NSSharingServicePicker(items: [item])
        self.model = model
        super.init()
        picker.delegate = self
    }

    func show(relativeTo view: NSView) {
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        // The chosen service holds on to the item from here.
        if model?.sharePicker === self {
            model?.sharePicker = nil
        }
    }
}

/// The processed image as something to share from File ▸ Share. Nothing
/// renders until a service asks for the file, and the file it gets carries
/// the export name.
struct ProcessedImageItem: Transferable {
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
        SentTransferredFile(try await model.renderCurrentImageForTransfer())
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

    /// Removes a render that has been superseded, after a grace period for
    /// any app still reading it.
    static func remove(_ render: Task<URL, any Error>) {
        Task.detached(priority: .background) {
            guard let file = try? await render.value else { return }
            try? await Task.sleep(for: .seconds(120))
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
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
                    guard !dragSource.isDragging, let key = model.transferRenderKey else { return }
                    let didBegin = dragSource.begin(
                        fileName: key.fileName,
                        fileType: key.contentType,
                        dragImage: model.processedPreview ?? model.sourcePreview
                    ) { [model] in
                        try await model.renderProcessedImageForTransfer(key)
                    }
                    // Most drops land a second or so later; start now so the
                    // file is ready, or nearly, by the time it’s asked for.
                    if didBegin {
                        model.prepareTransferRender(key)
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
    private(set) var isDragging = false

    func begin(
        fileName: String,
        fileType: UTType,
        dragImage: NSImage?,
        render: @escaping @Sendable @MainActor () async throws -> URL
    ) -> Bool {
        guard !isDragging,
              let event = NSApp.currentEvent, event.type == .leftMouseDragged,
              let view = event.window?.contentView else { return false }
        isDragging = true

        let promise = ProcessedImagePromise(fileName: fileName, render: render)
        let provider = NamedFilePromiseProvider(fileType: fileType.identifier, delegate: promise)
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
        return true
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

/// A file promise that puts the file’s name on the drag pasteboard up front.
/// Left to itself, the name is only promised, to be asked for later; a
/// receiver that reads it before the render is done, or doesn’t ask, names
/// the file after its type instead (“JPEG image”).
private final class NamedFilePromiseProvider: NSFilePromiseProvider {
    private static let suggestedFileNameType = NSPasteboard.PasteboardType(
        "com.apple.pasteboard.promised-suggested-file-name"
    )

    override func writingOptions(
        forType type: NSPasteboard.PasteboardType,
        pasteboard: NSPasteboard
    ) -> NSPasteboard.WritingOptions {
        if type == Self.suggestedFileNameType {
            return []
        }
        return super.writingOptions(forType: type, pasteboard: pasteboard)
    }
}

/// Writes the promised file: waits for the render, then copies it to exactly
/// the place the receiving app asked for.
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
