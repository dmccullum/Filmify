import AppKit
import GranularCore
import Foundation
import Observation
import ServiceManagement
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

struct ProcessingJob: Identifiable {
    let id = UUID()
    let sourceURL: URL
    var state: JobState
}

@MainActor
@Observable
final class AppModel {
    var operationMode: OperationMode = .drop
    var recipe: FilmRecipe = .classic35
    var selectedRecipeID = FilmRecipe.classic35.id
    var savedRecipes: [FilmRecipe] = []
    var showRecipeManager = false
    var showOriginal = false
    var activeCenterTarget: EffectCenterTarget?
    var isDropTargeted = false
    var outputOptions = OutputOptions()

    var dropOutputFolder: URL?
    var watchedInputFolder: URL?
    var watchedOutputFolder: URL?
    var isWatching = false
    var showMenuBarExtra = false

    var sourcePreview: NSImage?
    var processedPreview: NSImage?
    var selectedSourceURL: URL?
    var isRenderingPreview = false
    var isExporting = false
    var jobs: [ProcessingJob] = []
    var statusMessage = "Ready"
    var watchStatusMessage = "Choose Incoming and Finished folders, then start watching."
    var watchErrorMessage: String?
    var startupError: String?

    private var processingService: ImageProcessingService?
    private var previewTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var monitor: WatchedFolderMonitor?
    private var activeSecurityURLs: [URL] = []

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

        switch target {
        case .vignette:
            recipe.lightShaping.centerX = x
            recipe.lightShaping.centerY = y
        case .lensBlur:
            recipe.lensBlur.focusX = x
            recipe.lensBlur.focusY = y
        }
    }

    func finishCenterAdjustment() {
        activeCenterTarget = nil
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

    func modeDidChange() {
        if operationMode == .drop, jobs.isEmpty {
            statusMessage = "Ready"
        }
        scheduleWindowResize(for: operationMode, animated: true)
    }

    func scheduleWindowResize(for mode: OperationMode, animated: Bool = true) {
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            if animated {
                try? await Task.sleep(for: .milliseconds(55))
            }
            guard !Task.isCancelled, let self, self.operationMode == mode else { return }
            self.resizeWindow(for: mode, animated: animated)
        }
    }

    private func resizeWindow(for mode: OperationMode, animated: Bool) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
        var contentSize = mode == .drop
            ? NSSize(width: 700, height: 400)
            : NSSize(width: 1_080, height: 970)
        if let visibleFrame = window.screen?.visibleFrame {
            contentSize.height = min(contentSize.height, visibleFrame.height - 28)
        }
        let targetFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        var targetFrame = window.frame
        targetFrame.origin.x = window.frame.midX - targetFrameSize.width / 2
        targetFrame.origin.y = window.frame.maxY - targetFrameSize.height
        targetFrame.size = targetFrameSize

        if let visibleFrame = window.screen?.visibleFrame {
            targetFrame.origin.x = min(
                max(targetFrame.origin.x, visibleFrame.minX),
                visibleFrame.maxX - targetFrame.width
            )
            targetFrame.origin.y = min(
                max(targetFrame.origin.y, visibleFrame.minY),
                visibleFrame.maxY - targetFrame.height
            )
        }

        window.setFrame(targetFrame, display: true, animate: animated)
    }

    func selectRecipe(_ recipe: FilmRecipe) {
        selectedRecipeID = recipe.id
        self.recipe = recipe
        persistRecipeSelection()
        schedulePreview()
    }

    func recipeDidChange() {
        persistRecipeSelection()
        schedulePreview()
    }

    func saveCurrentAsRecipe() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Recipe name"
        field.stringValue = isSelectedRecipeCustom ? recipe.name : "My Recipe"

        let alert = NSAlert()
        alert.messageText = "Save Film Recipe"
        alert.informativeText = "This saves every adjustment and the global strength."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        var recipe = recipe
        recipe.id = "custom-\(UUID().uuidString)"
        recipe.name = name
        savedRecipes.append(recipe)
        persistRecipes()
        selectRecipe(recipe)
        statusMessage = "Saved recipe “\(name)”"
    }

    func updateSelectedRecipe() {
        guard let index = savedRecipes.firstIndex(where: { $0.id == selectedRecipeID }) else { return }
        var updated = recipe
        updated.id = savedRecipes[index].id
        updated.name = savedRecipes[index].name
        savedRecipes[index] = updated
        recipe = updated
        persistRecipes()
        persistRecipeSelection()
        statusMessage = "Updated recipe “\(updated.name)”"
    }

    func deleteSelectedRecipe() {
        guard let index = savedRecipes.firstIndex(where: { $0.id == selectedRecipeID }) else { return }
        let name = savedRecipes[index].name

        let alert = NSAlert()
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = "This recipe will be permanently deleted. This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        savedRecipes.remove(at: index)
        persistRecipes()
        selectRecipe(.classic35)
        statusMessage = "Deleted recipe “\(name)”"
    }

    func renameRecipe(id: String, to proposedName: String) -> Bool {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !savedRecipes.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }),
              let index = savedRecipes.firstIndex(where: { $0.id == id }) else { return false }

        savedRecipes[index].name = name
        if selectedRecipeID == id {
            recipe.name = name
            persistRecipeSelection()
        }
        persistRecipes()
        statusMessage = "Renamed recipe to “\(name)”"
        return true
    }

    func deleteRecipe(id: String) {
        guard let index = savedRecipes.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedRecipeID == id
        let name = savedRecipes[index].name
        savedRecipes.remove(at: index)
        persistRecipes()
        if wasSelected {
            selectRecipe(.classic35)
        }
        statusMessage = "Deleted recipe “\(name)”"
    }

    func resetLightShaping() {
        recipe.lightShaping = currentRecipe.lightShaping
        schedulePreview()
    }

    func resetTone() {
        recipe.tone = currentRecipe.tone
        schedulePreview()
    }

    func resetLensBlur() {
        recipe.lensBlur = currentRecipe.lensBlur
        schedulePreview()
    }

    func resetDiffusion() {
        recipe.diffusion = currentRecipe.diffusion
        schedulePreview()
    }

    func resetHalation() {
        recipe.halation = currentRecipe.halation
        schedulePreview()
    }

    func resetLandscapeGlow() {
        recipe.landscapeGlow = currentRecipe.landscapeGlow
        schedulePreview()
    }

    func resetGrain() {
        recipe.grain = currentRecipe.grain
        schedulePreview()
    }

    func randomizeGrain() {
        recipe.grain.seed = UInt32.random(in: 1 ..< 1_000_003)
        schedulePreview()
    }

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

    func chooseDropOutputFolder() {
        guard let url = chooseFolder(title: "Choose Instant Output Folder") else { return }
        setFolder(url, key: BookmarkKey.dropOutput) { dropOutputFolder = $0 }
    }

    func chooseWatchedInputFolder() {
        guard let url = chooseFolder(title: "Choose Incoming Folder") else { return }
        let shouldResume = isWatching
        if setFolder(url, key: BookmarkKey.watchInput, assignment: { watchedInputFolder = $0 }), shouldResume {
            startWatching()
        }
    }

    func chooseWatchedOutputFolder() {
        guard let url = chooseFolder(title: "Choose Finished Folder") else { return }
        let shouldResume = isWatching
        if setFolder(url, key: BookmarkKey.watchOutput, assignment: { watchedOutputFolder = $0 }), shouldResume {
            startWatching()
        }
    }

    @discardableResult
    func processInstantly(_ urls: [URL], destinationOverride: URL? = nil) async -> Set<URL> {
        persistRecipeSelection()
        let supported = urls.filter(Self.isSupportedImage)
        guard !supported.isEmpty else {
            statusMessage = "No supported images in that drop"
            return []
        }

        if dropOutputFolder == nil, destinationOverride == nil {
            chooseDropOutputFolder()
        }
        guard let destination = destinationOverride ?? dropOutputFolder else {
            statusMessage = "Choose an output folder to continue"
            return []
        }
        guard Self.isExistingDirectory(destination) else {
            let message = destinationOverride == nil
                ? "Instant output folder is no longer available. Choose it again."
                : "Finished folder is no longer available. Choose it again."
            statusMessage = message
            if destinationOverride != nil {
                watchErrorMessage = message
                watchStatusMessage = message
            }
            return []
        }
        guard let processingService else {
            statusMessage = startupError ?? "The image engine is unavailable"
            return []
        }

        var completed: Set<URL> = []
        for url in supported {
            let job = ProcessingJob(sourceURL: url, state: .queued)
            jobs.insert(job, at: 0)
            let id = job.id
            updateJob(id, state: .processing)
            statusMessage = "Processing \(url.lastPathComponent)…"

            let gainedSourceAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gainedSourceAccess { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let output = try await processingService.process(
                    sourceURL: url,
                    destinationFolder: destination,
                    recipe: recipe,
                    options: outputOptions
                )
                updateJob(id, state: .finished(output))
                statusMessage = "Finished \(url.lastPathComponent)"
                completed.insert(url)
                if destinationOverride != nil {
                    watchErrorMessage = nil
                    watchStatusMessage = "Finished \(url.lastPathComponent)"
                }
            } catch {
                updateJob(id, state: .failed(error.localizedDescription))
                let message = "Couldn’t process \(url.lastPathComponent): \(error.localizedDescription)"
                statusMessage = message
                if destinationOverride != nil {
                    watchErrorMessage = message
                    watchStatusMessage = message
                }
            }
        }
        return completed
    }

    func exportEditedImage() {
        guard let sourceURL = selectedSourceURL else { return }
        let type = resolvedOutputType(for: sourceURL)
        let panel = NSSavePanel()
        panel.title = "Export Filmified Image"
        panel.prompt = "Export"
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent
            + " — Granular."
            + (type.preferredFilenameExtension ?? "tiff")
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        Task { await exportEditor(sourceURL: sourceURL, destinationURL: destinationURL) }
    }

    private func exportEditor(sourceURL: URL, destinationURL: URL) async {
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

    func schedulePreview() {
        guard operationMode == .edit,
              let selectedSourceURL,
              let processingService else { return }
        previewTask?.cancel()
        let recipe = recipe
        isRenderingPreview = true
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            do {
                let data = try await processingService.renderPreview(
                    sourceURL: selectedSourceURL,
                    recipe: recipe,
                    maximumDimension: 2_400
                )
                guard !Task.isCancelled else { return }
                processedPreview = NSImage(data: data)
                isRenderingPreview = false
                statusMessage = selectedSourceURL.lastPathComponent
            } catch {
                isRenderingPreview = false
                statusMessage = "Preview failed: \(error.localizedDescription)"
            }
        }
    }

    func toggleWatching() {
        if isWatching {
            stopWatching()
        } else {
            startWatching()
        }
    }

    func startWatching() {
        guard let input = watchedInputFolder, let output = watchedOutputFolder else {
            let message = "Choose both watched folders first."
            statusMessage = message
            watchErrorMessage = message
            watchStatusMessage = message
            isWatching = false
            return
        }
        guard Self.isExistingDirectory(input) else {
            let message = "Incoming folder is no longer available. Choose it again."
            statusMessage = message
            watchErrorMessage = message
            watchStatusMessage = message
            isWatching = false
            return
        }
        guard Self.isExistingDirectory(output) else {
            let message = "Finished folder is no longer available. Choose it again."
            statusMessage = message
            watchErrorMessage = message
            watchStatusMessage = message
            isWatching = false
            return
        }
        guard input.standardizedFileURL != output.standardizedFileURL else {
            let message = "Incoming and Finished must be different folders."
            statusMessage = message
            watchErrorMessage = message
            watchStatusMessage = message
            isWatching = false
            return
        }
        guard !output.path.hasPrefix(input.path + "/") else {
            let message = "Finished cannot be inside Incoming."
            statusMessage = message
            watchErrorMessage = message
            watchStatusMessage = message
            isWatching = false
            return
        }

        if let existingMonitor = monitor {
            Task { await existingMonitor.stop() }
        }
        let monitor = WatchedFolderMonitor()
        self.monitor = monitor
        isWatching = true
        showMenuBarExtra = true
        watchErrorMessage = nil
        watchStatusMessage = "Watching \(input.lastPathComponent)"
        statusMessage = watchStatusMessage
        Task {
            await monitor.start(folder: input) { [weak self] urls in
                guard let self else { return [] }
                return await self.processInstantly(urls, destinationOverride: output)
            } errorHandler: { [weak self] message in
                await monitor.stop()
                guard let self else { return }
                await self.watchingFailed(message)
            }
        }
    }

    func stopWatching() {
        if let monitor {
            Task { await monitor.stop() }
        }
        monitor = nil
        isWatching = false
        showMenuBarExtra = false
        watchErrorMessage = nil
        watchStatusMessage = "Watching paused"
        statusMessage = watchStatusMessage
    }

    func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealLastOutput() {
        reveal(lastFinishedURL)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusMessage = "Launch at Login: \(error.localizedDescription)"
        }
    }

    private func updateJob(_ id: UUID, state: JobState) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = state
    }

    private func chooseFolder(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    @discardableResult
    private func setFolder(_ url: URL, key: String, assignment: (URL) -> Void) -> Bool {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope)
            UserDefaults.standard.set(data, forKey: key)
            retainSecurityScope(for: url)
            assignment(url)
            watchErrorMessage = nil
            return true
        } catch {
            statusMessage = "Couldn’t remember that folder: \(error.localizedDescription)"
            return false
        }
    }

    private func watchingFailed(_ message: String) {
        guard isWatching else { return }
        monitor = nil
        isWatching = false
        watchErrorMessage = message
        watchStatusMessage = message
        statusMessage = message
    }

    private func restoreFolder(forKey key: String, assignment: (URL) -> Void) {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            retainSecurityScope(for: url)
            assignment(url)
            if isStale {
                let refreshed = try url.bookmarkData(options: .withSecurityScope)
                UserDefaults.standard.set(refreshed, forKey: key)
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func retainSecurityScope(for url: URL) {
        guard !activeSecurityURLs.contains(url) else { return }
        if url.startAccessingSecurityScopedResource() {
            activeSecurityURLs.append(url)
        }
    }

    private func restoreRecipes() {
        guard let data = UserDefaults.standard.data(forKey: RecipeKey.saved),
              let decoded = try? JSONDecoder().decode([FilmRecipe].self, from: data) else { return }
        savedRecipes = decoded
    }

    private func persistRecipes() {
        guard let data = try? JSONEncoder().encode(savedRecipes) else { return }
        UserDefaults.standard.set(data, forKey: RecipeKey.saved)
    }

    private func restoreRecipeSelection() {
        let defaults = UserDefaults.standard
        guard let storedID = defaults.string(forKey: RecipeKey.selectedID),
              let selected = availableRecipes.first(where: { $0.id == storedID }) else {
            selectRecipe(.classic35)
            return
        }

        selectedRecipeID = selected.id
        if defaults.bool(forKey: RecipeKey.isModified),
           let data = defaults.data(forKey: RecipeKey.working),
           var working = try? JSONDecoder().decode(FilmRecipe.self, from: data) {
            // Keep the originating recipe identity so Reset and Update still work.
            working.id = selected.id
            working.name = selected.name
            recipe = working
        } else {
            recipe = selected
        }
        persistRecipeSelection()
    }

    private func persistRecipeSelection() {
        let defaults = UserDefaults.standard
        defaults.set(selectedRecipeID, forKey: RecipeKey.selectedID)
        defaults.set(isRecipeModified, forKey: RecipeKey.isModified)
        if let data = try? JSONEncoder().encode(recipe) {
            defaults.set(data, forKey: RecipeKey.working)
        }
    }

    private func resolvedOutputType(for sourceURL: URL) -> UTType {
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

    private static let supportedImageTypes: [UTType] = [.jpeg, .heic, .png, .tiff]

    private static func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return supportedImageTypes.contains(type)
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

private enum BookmarkKey {
    static let dropOutput = "folders.dropOutput"
    static let watchInput = "folders.watchInput"
    static let watchOutput = "folders.watchOutput"
}

private enum RecipeKey {
    static let saved = "recipes.saved"
    static let selectedID = "recipes.selectedID"
    static let working = "recipes.working"
    static let isModified = "recipes.isModified"
}
