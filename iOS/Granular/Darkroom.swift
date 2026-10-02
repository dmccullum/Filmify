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
        didSet { scheduleRecipeSave() }
    }

    /// The recipe the look started from, which Revert goes back to.
    private(set) var selectedRecipeID: String
    private(set) var savedRecipes: [FilmRecipe]

    var availableRecipes: [FilmRecipe] { FilmRecipe.builtIns + savedRecipes }

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
        savedRecipes = saved
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
