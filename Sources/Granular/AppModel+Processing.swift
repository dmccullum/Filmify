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

    func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealLastOutput() {
        reveal(lastFinishedURL)
    }

    func updateJob(_ id: UUID, state: JobState) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = state
    }
}
