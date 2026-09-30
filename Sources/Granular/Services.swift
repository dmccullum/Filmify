import AppKit

/// Services ▸ “Filmify with Granular” for images selected in Finder or any
/// app that offers files. They’re processed with the current recipe, just as
/// if they’d been dropped on the film strip. Declared under NSServices in
/// Info.plist, so macOS launches Granular to handle it if it isn’t running.
@MainActor
final class ImageServiceProvider: NSObject {
    static let shared = ImageServiceProvider()

    /// Set as the app is created, before any service request can arrive.
    var model: AppModel?

    @objc(filmifyImages:userData:error:)
    func filmifyImages(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        let images = urls.filter(AppModel.isSupportedImage)
        guard let model, !images.isEmpty else {
            error.pointee = "Granular can only filmify JPEG, HEIC, PNG and TIFF images." as NSString
            return
        }

        // Stay in the background unless there’s a folder to ask for.
        if model.dropOutputFolder == nil {
            NSApp.activate()
        }
        Task { await model.processInstantly(images) }
    }
}
