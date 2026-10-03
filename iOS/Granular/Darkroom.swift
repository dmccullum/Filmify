import GranularCore
import ImageIO
import Photos
import PhotosUI
import SwiftUI

/// The phone's Instant mode: photos picked from the library are developed one
/// at a time with the loaded recipe and saved straight back to Photos.
@MainActor
@Observable
final class Darkroom {
    struct Job: Identifiable, Equatable {
        enum State: Equatable {
            case processing
            case finished(URL)
            case failed(String)
        }

        let id = UUID()
        let item: PhotosPickerItem
        var sourceURL: URL?
        var state: State = .processing
        /// Developed but not in the library yet, because Photos access was refused.
        var isUnsaved = false

        var outputURL: URL? {
            if case .finished(let url) = state { return url }
            return nil
        }
    }

    /// Newest first: the lead job is the one in the gate.
    private(set) var jobs: [Job] = []
    private(set) var batch: ProcessingBatch?
    private(set) var thumbnails: [UUID: CGImage] = [:]

    /// The look loaded in the camera: a recipe as chosen, or as adjusted in
    /// Edit mode. Instant and Edit share it, as they do on the Mac.
    var recipe: FilmRecipe {
        didSet {
            scheduleRecipeSave()
            recordChange(from: oldValue)
        }
    }

    /// The recipe the look started from, which Revert goes back to.
    private(set) var selectedRecipeID: String
    private var library: RecipeLibrary

    /// The recipes made on this phone or imported, in the order they're listed.
    var savedRecipes: [FilmRecipe] { library.saved }

    /// The sheet over the camera, if any. It lives here so both recipe menus,
    /// and a recipe file being opened, can present it.
    var recipeSheet: RecipeSheet?
    /// The last recipe imported, which the library scrolls to.
    private(set) var lastImportedID: String?
    /// What went wrong importing recipe files, for the library to show.
    var importAlert: ImportAlert?

    var availableRecipes: [FilmRecipe] { library.all }

    var currentRecipe: FilmRecipe {
        availableRecipes.first { $0.id == selectedRecipeID } ?? .classic35
    }

    var isRecipeModified: Bool { recipe != currentRecipe }

    var recipeDisplayName: String { isRecipeModified ? "Custom" : currentRecipe.name }

    /// Every frame developed since the app was installed.
    private(set) var exposures: Int {
        didSet { UserDefaults.standard.set(exposures, forKey: Keys.exposures) }
    }

    var unsavedCount: Int { jobs.count { $0.isUnsaved } }

    private var queue: [PhotosPickerItem] = []
    private var isRunning = false
    private var settle: (id: UUID, continuation: CheckedContinuation<Void, Never>)?
    private let service: ImageProcessingService?
    private let roll: URL

    @ObservationIgnored private var recipeSaveTask: Task<Void, Never>?

    /// Earlier looks, newest last, for Undo and Redo.
    private var undoStack: [FilmRecipe] = []
    private var redoStack: [FilmRecipe] = []
    @ObservationIgnored private var isRestoring = false
    @ObservationIgnored private var isAdjusting = false
    /// Changes made together undo together: those in one action, like a
    /// stock that also turns Film on, and all of a slider's drag.
    @ObservationIgnored private var isGrouping = false
    @ObservationIgnored private var groupEnd: Task<Void, Never>?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private enum Keys {
        /// Earlier builds kept only the chosen built-in, by ID.
        static let legacyRecipe = "recipe"
        static let exposures = "exposures"
    }

    /// How many developed frames are kept on hand for viewing and sharing.
    private static let keptFrames = 12

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: RecipeKey.saved)
            .flatMap { try? JSONDecoder().decode([FilmRecipe].self, from: $0) } ?? []
        library = RecipeLibrary(saved: saved)
        let storedID = defaults.string(forKey: RecipeKey.selectedID) ?? defaults.string(forKey: Keys.legacyRecipe)
        let selected = (FilmRecipe.builtIns + saved).first { $0.id == storedID } ?? .classic35
        selectedRecipeID = selected.id
        if defaults.bool(forKey: RecipeKey.isModified),
           let data = defaults.data(forKey: RecipeKey.working),
           let working = try? JSONDecoder().decode(FilmRecipe.self, from: data) {
            // Keep the originating recipe's identity so Revert still finds it.
            recipe = selected.applyingAdjustments(of: working)
        } else {
            recipe = selected
        }
        exposures = defaults.integer(forKey: Keys.exposures)
        service = try? ImageProcessingService()
        // A fresh roll every launch: last session's frames are already in Photos.
        roll = FileManager.default.temporaryDirectory.appending(path: "Roll", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: roll)
        try? FileManager.default.createDirectory(at: roll, withIntermediateDirectories: true)
        if defaults.object(forKey: Keys.legacyRecipe) != nil {
            persistRecipe()
            defaults.removeObject(forKey: Keys.legacyRecipe)
        }
    }

    // MARK: Recipes

    func selectRecipe(_ recipe: FilmRecipe) {
        selectedRecipeID = recipe.id
        self.recipe = recipe
        persistRecipe()
    }

    /// Puts the look back to the recipe it started from.
    func revertRecipe() {
        recipe = currentRecipe
        persistRecipe()
    }

    // MARK: Library

    /// Whether the look has edits that Update would save into a recipe of the
    /// phone's own.
    var canUpdateSelectedRecipe: Bool {
        isRecipeModified && library.contains(savedID: selectedRecipeID)
    }

    func isSavedRecipe(_ id: String) -> Bool {
        library.contains(savedID: id)
    }

    /// Saves the look as a new recipe and puts it to use, as is.
    @discardableResult
    func saveCurrentAsRecipe(named name: String, canister: String?) -> FilmRecipe? {
        guard let saved = library.save(recipe, named: name, canister: canister) else { return nil }
        selectedRecipeID = saved.id
        setLook(saved)
        persistRecipes()
        persistRecipe()
        return saved
    }

    /// Saves the edits into the saved recipe they started from.
    func updateSelectedRecipe() {
        guard canUpdateSelectedRecipe, let updated = library.update(id: selectedRecipeID, with: recipe) else { return }
        setLook(updated)
        persistRecipes()
        persistRecipe()
    }

    @discardableResult
    func renameRecipe(id: String, to name: String) -> Bool {
        guard library.rename(id: id, to: name) else { return false }
        if selectedRecipeID == id, let renamed = savedRecipes.first(where: { $0.id == id }) {
            var look = recipe
            look.name = renamed.name
            setLook(look)
        }
        persistRecipes()
        persistRecipe()
        return true
    }

    func setCanister(_ canister: String?, forRecipe id: String) {
        library.setCanister(canister, for: id)
        if selectedRecipeID == id {
            var look = recipe
            look.canister = canister
            setLook(look)
        }
        persistRecipes()
        persistRecipe()
    }

    /// Saves a copy of any recipe, in the same canister.
    @discardableResult
    func duplicateRecipe(id: String) -> FilmRecipe? {
        guard let original = availableRecipes.first(where: { $0.id == id }),
              let copy = library.duplicate(id: id, canister: CanisterDesign.resolved(for: original).id) else { return nil }
        persistRecipes()
        return copy
    }

    /// Deletes a saved recipe. If it was in use the look stays as it is and
    /// simply no longer belongs to a saved recipe.
    func deleteRecipe(id: String) {
        guard library.contains(savedID: id) else { return }
        library.delete(id: id)
        if selectedRecipeID == id {
            selectedRecipeID = FilmRecipe.classic35.id
            setLook(FilmRecipe.classic35.applyingAdjustments(of: recipe))
        }
        persistRecipes()
        persistRecipe()
    }

    func moveSavedRecipes(fromOffsets source: IndexSet, toOffset destination: Int) {
        library.move(fromOffsets: source, toOffset: destination)
        persistRecipes()
    }

    /// Adds the recipes in these files to the library, each under a name of
    /// its own. Files that can't be read are reported in `importAlert`.
    @discardableResult
    func importRecipes(from urls: [URL]) -> (imported: [FilmRecipe], failures: [(String, Error)]) {
        var decoded: [FilmRecipe] = []
        var failures: [(String, Error)] = []
        for url in urls {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let file = try RecipeFile.decode(
                    Data(contentsOf: url),
                    fallbackName: url.deletingPathExtension().lastPathComponent
                )
                decoded.append(file.recipe)
            } catch {
                failures.append((url.lastPathComponent, error))
            }
        }
        let imported = library.importing(decoded)
        if !imported.isEmpty {
            persistRecipes()
            lastImportedID = imported.last?.id
        }
        if let failure = failures.first {
            importAlert = ImportAlert(
                title: failures.count == 1
                    ? "“\(failure.0)” couldn’t be imported."
                    : "\(failures.count) files couldn’t be imported.",
                message: failure.1.localizedDescription
            )
        }
        return (imported, failures)
    }

    func persistRecipes() {
        guard let data = try? JSONEncoder().encode(savedRecipes) else { return }
        UserDefaults.standard.set(data, forKey: RecipeKey.saved)
    }

    /// Sets the look without a step on the undo stack: library changes
    /// aren't undone with the look.
    private func setLook(_ look: FilmRecipe) {
        let wasRestoring = isRestoring
        isRestoring = true
        defer { isRestoring = wasRestoring }
        recipe = look
    }

    // MARK: Undo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        endGroup()
        redoStack.append(recipe)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        endGroup()
        undoStack.append(recipe)
        restore(next)
    }

    /// Holds a control's changes together from touch down to touch up,
    /// however long it pauses along the way.
    func setAdjusting(_ adjusting: Bool) {
        isAdjusting = adjusting
        if !adjusting, isGrouping { scheduleGroupEnd() }
    }

    /// A look carries the identity of the recipe it came from, so putting one
    /// back puts back the choice of recipe too.
    private func restore(_ look: FilmRecipe) {
        isRestoring = true
        defer { isRestoring = false }
        if availableRecipes.contains(where: { $0.id == look.id }) {
            selectedRecipeID = look.id
        }
        recipe = look
        persistRecipe()
    }

    private func recordChange(from old: FilmRecipe) {
        guard !isRestoring, old != recipe else { return }
        if !isGrouping {
            isGrouping = true
            undoStack.append(old)
            if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        scheduleGroupEnd()
    }

    /// Ends the group once the current action has finished, unless a
    /// control is still held.
    private func scheduleGroupEnd() {
        groupEnd?.cancel()
        guard !isAdjusting else { return }
        groupEnd = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.isGrouping = false
        }
    }

    private func endGroup() {
        groupEnd?.cancel()
        groupEnd = nil
        isGrouping = false
    }

    private static let undoLimit = 100

    func persistRecipe() {
        recipeSaveTask?.cancel()
        recipeSaveTask = nil
        let defaults = UserDefaults.standard
        defaults.set(selectedRecipeID, forKey: RecipeKey.selectedID)
        defaults.set(isRecipeModified, forKey: RecipeKey.isModified)
        if let data = try? JSONEncoder().encode(recipe) {
            defaults.set(data, forKey: RecipeKey.working)
        }
    }

    /// A slider changes the recipe on every tick; save once it rests.
    private func scheduleRecipeSave() {
        recipeSaveTask?.cancel()
        recipeSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persistRecipe()
        }
    }

    /// A frame developed in Edit mode and saved to the library.
    func recordExposure() {
        exposures += 1
    }

    // MARK: Instant

    func develop(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        queue.append(contentsOf: items)
        if batch == nil {
            batch = ProcessingBatch(total: items.count)
        } else {
            batch?.add(items.count)
        }
        guard !isRunning else { return }
        isRunning = true
        Task { await run() }
    }

    func retry(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        jobs.removeAll { $0.id == id }
        thumbnails[id] = nil
        develop([job.item])
    }

    /// Called by the film once a frame has wound clear of the gate, so the next
    /// exposure doesn't land on top of the last.
    func filmDidSettle() {
        settle?.continuation.resume()
        settle = nil
    }

    func saveUnsaved() {
        Task {
            for job in jobs where job.isUnsaved {
                guard let url = job.outputURL else { continue }
                await save(url, for: job.id)
            }
            if unsavedCount > 0, await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .denied,
               let settings = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(settings)
            }
        }
    }

    // MARK: Processing

    private func run() async {
        while !queue.isEmpty {
            let item = queue.removeFirst()
            let job = Job(item: item)
            jobs.insert(job, at: 0)
            await develop(job)
            await waitForFilm()
        }
        isRunning = false
        batch = nil
        trimRoll()
    }

    private func develop(_ job: Job) async {
        let folder = roll.appending(path: job.id.uuidString, directoryHint: .isDirectory)
        do {
            guard let service else { throw DarkroomError.rendererUnavailable }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let picked = try await job.item.loadTransferable(type: PickedPhoto.self) else {
                throw DarkroomError.photoUnavailable
            }
            let source = folder.appending(path: picked.url.lastPathComponent)
            try FileManager.default.moveItem(at: picked.url, to: source)
            try? FileManager.default.removeItem(at: picked.url.deletingLastPathComponent())
            update(job.id) { $0.sourceURL = source }
            thumbnails[job.id] = await Self.thumbnail(of: source)

            let output = try await service.process(
                sourceURL: source,
                destinationFolder: folder,
                recipe: recipe,
                options: OutputOptions()
            )
            try? FileManager.default.removeItem(at: source)
            thumbnails[job.id] = await Self.thumbnail(of: output) ?? thumbnails[job.id]
            update(job.id) { $0.state = .finished(output) }
            batch?.recordSuccess(output: output)
            exposures += 1
            await save(output, for: job.id)
        } catch {
            update(job.id) { $0.state = .failed(error.localizedDescription) }
            batch?.recordFailure()
        }
    }

    private func save(_ url: URL, for id: UUID) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        var saved = false
        if status == .authorized || status == .limited {
            saved = (try? await Self.addToLibrary(url)) != nil
        }
        update(id) { $0.isUnsaved = !saved }
    }

    /// Photos runs the change block on its own queue, so it's built here, away
    /// from the main actor, rather than inherit the darkroom's isolation.
    nonisolated static func addToLibrary(_ url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
        }
    }

    private func waitForFilm() async {
        let id = UUID()
        await withCheckedContinuation { continuation in
            settle = (id, continuation)
            // Never hold up the roll for long if the film isn't on screen to say so.
            Task {
                try? await Task.sleep(for: .seconds(4))
                if settle?.id == id { filmDidSettle() }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    /// Lets go of frames that have long since wound off the strip.
    private func trimRoll() {
        guard jobs.count > Self.keptFrames else { return }
        for job in jobs[Self.keptFrames...] where !job.isUnsaved {
            try? FileManager.default.removeItem(at: roll.appending(path: job.id.uuidString))
            thumbnails[job.id] = nil
        }
        jobs = Array(jobs.prefix(Self.keptFrames)) + jobs.dropFirst(Self.keptFrames).filter(\.isUnsaved)
    }

    nonisolated static func thumbnail(of url: URL, maxPixelSize: Int = 720) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }
}

/// The sheets that can open over the camera.
enum RecipeSheet: Identifiable {
    case save
    case library

    var id: Self { self }
}

/// A failed import, as the library reports it.
struct ImportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum DarkroomError: LocalizedError {
    case rendererUnavailable
    case photoUnavailable

    var errorDescription: String? {
        switch self {
        case .rendererUnavailable: "The film renderer couldn’t start."
        case .photoUnavailable: "The photo couldn’t be loaded from the library."
        }
    }
}

/// A photo from the library, copied out as its original file so it keeps its
/// format, size and metadata.
struct PickedPhoto: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let folder = FileManager.default.temporaryDirectory
                .appending(path: "Picked-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appending(path: received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedPhoto(url: copy)
        }
    }
}
