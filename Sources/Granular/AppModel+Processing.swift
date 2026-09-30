import AppKit
import GranularCore
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// Instant mode: processing images straight to the output folder.
extension AppModel {
    func chooseDropOutputFolder() {
        guard let url = chooseFolder(title: "Choose Instant Output Folder") else { return }
        useDropOutputFolder(url)
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

        // Ask Each Time develops into a temporary folder first; the Save panel
        // comes once the last frame has wound on.
        let asksWhereToSave = destinationOverride == nil && asksWhereToSaveInstantly
        let destination: URL
        if asksWhereToSave {
            do {
                destination = try UnsavedOutputs.makeFolder()
            } catch {
                statusMessage = "Couldn’t prepare a place to develop the images: \(error.localizedDescription)"
                return []
            }
        } else {
            if dropOutputFolder == nil, destinationOverride == nil {
                chooseDropOutputFolder()
            }
            guard let chosen = destinationOverride ?? dropOutputFolder else {
                statusMessage = "Choose an output folder to continue"
                return []
            }
            guard Self.isExistingDirectory(chosen) else {
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
            destination = chosen
        }
        guard let processingService else {
            statusMessage = startupError ?? "The image engine is unavailable"
            return []
        }

        let batchID = beginBatch(of: supported.count, isWatched: destinationOverride != nil, asksWhereToSave: asksWhereToSave)
        defer { endBatchRun(batchID) }

        var completed: Set<URL> = []
        for url in supported {
            // Cancelling stops between images; the one in the gate still finishes.
            guard !isBatchCancelled(batchID) else { break }

            let job = ProcessingJob(sourceURL: url, state: .queued)
            jobs.insert(job, at: 0)
            let id = job.id
            if let destinationOverride {
                jobDestinationOverrides[id] = destinationOverride
            }
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
                if asksWhereToSave {
                    unsavedJobIDs.insert(id)
                    jobsAwaitingSavePrompt.append(id)
                }
                recordBatchResult(batchID, output: output)
                if destinationOverride != nil {
                    watchErrorMessage = nil
                    watchStatusMessage = "Finished \(url.lastPathComponent)"
                }
            } catch {
                updateJob(id, state: .failed(error.localizedDescription))
                let message = "Couldn’t process \(url.lastPathComponent): \(error.localizedDescription)"
                statusMessage = message
                recordBatchResult(batchID, output: nil)
                if destinationOverride != nil {
                    watchErrorMessage = message
                    watchStatusMessage = message
                }
            }
        }
        // Say so when part of a drop wasn’t something Granular can read.
        let skipped = urls.count - supported.count
        if skipped > 0, !isBatchCancelled(batchID) {
            statusMessage = skipped == 1
                ? "Skipped 1 file that isn’t a supported image"
                : "Skipped \(skipped) files that aren’t supported images"
        }
        return completed
    }

    func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealLastOutput() {
        // A frame still waiting to be saved has nothing worth revealing yet.
        let saved = jobs.lazy.compactMap { job -> URL? in
            guard case .finished(let url) = job.state, !self.unsavedJobIDs.contains(job.id) else { return nil }
            return url
        }
        reveal(saved.first)
    }

    func updateJob(_ id: UUID, state: JobState) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = state
    }

    // MARK: Frames on the strip

    func job(_ id: UUID) -> ProcessingJob? {
        jobs.first { $0.id == id }
    }

    /// Whether a URL is something Granular itself wrote, so dragging a frame
    /// out and letting go over the window doesn’t process it a second time.
    func isInstantOutput(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return jobs.contains {
            if case .finished(let output) = $0.state { return output.standardizedFileURL.path == path }
            return false
        }
    }

    func openOutput(of id: UUID) {
        guard case .finished(let output) = job(id)?.state else { return }
        NSWorkspace.shared.open(output)
    }

    func openOutput(of id: UUID, withApplicationAt application: URL) {
        guard case .finished(let output) = job(id)?.state else { return }
        NSWorkspace.shared.open([output], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Puts the processed file on the pasteboard the way Finder does, so it
    /// pastes as a file in Finder and as an attachment in Mail or Messages.
    func copyOutput(of id: UUID) {
        guard case .finished(let output) = job(id)?.state else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([output as NSURL])
    }

    /// Opens the original, not the processed copy, so it can be refined from scratch.
    func openSourceInEditMode(of id: UUID) {
        guard let job = job(id) else { return }
        openForEditing([job.sourceURL])
    }

    func revealSource(of id: UUID) {
        reveal(job(id)?.sourceURL)
    }

    func moveOutputToTrash(of id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              case .finished(let output) = jobs[index].state else { return }
        // An unsaved frame only exists in the temporary folder: discarding it is final.
        if unsavedJobIDs.contains(id) {
            discardUnsaved(id)
            return
        }
        do {
            try FileManager.default.trashItem(at: output, resultingItemURL: nil)
            jobs.remove(at: index)
            jobDestinationOverrides[id] = nil
            statusMessage = "Moved \(output.lastPathComponent) to the Trash"
        } catch {
            statusMessage = "Couldn’t move \(output.lastPathComponent) to the Trash: \(error.localizedDescription)"
        }
    }

    /// Takes the spoiled frame off the strip and exposes the original again,
    /// into the folder it was headed for.
    func retryJob(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              case .failed = jobs[index].state else { return }
        let source = jobs[index].sourceURL
        let destination = jobDestinationOverrides.removeValue(forKey: id)
        jobs.remove(at: index)
        Task { await processInstantly([source], destinationOverride: destination) }
    }

    // MARK: Output folder

    func useDropOutputFolder(_ url: URL) {
        let previous = dropOutputFolder
        guard setFolder(url, key: BookmarkKey.dropOutput, assignment: { dropOutputFolder = $0 }) else { return }
        asksWhereToSaveInstantly = false
        if let previous {
            rememberRecentDropOutputFolder(previous)
        }
        rememberRecentDropOutputFolder(url)
    }

    /// Switches to a folder from the recent list, which is only reachable
    /// through its saved bookmark until it’s chosen again.
    func useRecentDropOutputFolder(_ url: URL) {
        let gainedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if gainedAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard Self.isExistingDirectory(url) else {
            statusMessage = "“\(url.lastPathComponent)” is no longer available"
            recentDropOutputFolders = recentOutputFolders().filter { $0 != url }
            saveRecentDropOutputFolders()
            return
        }
        useDropOutputFolder(url)
    }

    /// The current output folder followed by recent ones, for the footer pop-up.
    func recentOutputFolders() -> [URL] {
        if recentDropOutputFolders == nil {
            recentDropOutputFolders = loadRecentDropOutputFolders()
        }
        var folders = recentDropOutputFolders ?? []
        if let dropOutputFolder {
            folders = RecentFolders.adding(dropOutputFolder, to: folders)
        }
        return folders
    }

    func revealDropOutputFolder() {
        guard let dropOutputFolder else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dropOutputFolder.path)
    }

    private func rememberRecentDropOutputFolder(_ url: URL) {
        recentDropOutputFolders = RecentFolders.adding(url, to: recentOutputFolders())
        saveRecentDropOutputFolders()
    }

    private func loadRecentDropOutputFolders() -> [URL] {
        let bookmarks = UserDefaults.standard.array(forKey: Self.recentDropOutputsKey) as? [Data] ?? []
        return bookmarks.compactMap { data in
            var isStale = false
            return try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
    }

    private func saveRecentDropOutputFolders() {
        let bookmarks = (recentDropOutputFolders ?? []).compactMap { url -> Data? in
            let gainedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gainedAccess { url.stopAccessingSecurityScopedResource() }
            }
            return try? url.bookmarkData(options: .withSecurityScope)
        }
        UserDefaults.standard.set(bookmarks, forKey: Self.recentDropOutputsKey)
    }

    private static let recentDropOutputsKey = "folders.recentDropOutputs"
}
