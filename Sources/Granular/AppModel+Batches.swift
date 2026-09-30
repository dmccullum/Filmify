import AppKit
import GranularCore
import Foundation

/// A batch in flight, with what the notification at its end will need.
struct ActiveBatch: Identifiable, Equatable {
    let id = UUID()
    var progress: ProcessingBatch
    let recipeName: String?
    let isWatched: Bool
    /// Drops made mid-batch run their own loop; the batch ends with the last one.
    var runs = 1
}

// Instant mode: batch progress, cancelling, and reporting back through the
// Dock tile and Notification Center while Granular is in the background.
extension AppModel {
    /// The batch the camera back counts through: a drop, or else a watched burst.
    var displayedBatch: ActiveBatch? {
        instantBatch ?? watchBurst
    }

    var canCancelProcessing: Bool {
        guard let instantBatch else { return false }
        return !instantBatch.progress.isCancelled
    }

    /// Stops a drop batch after the image in the gate. Watched folders aren’t
    /// cancelled this way: their monitor would only pick the images up again.
    func cancelInstantProcessing() {
        guard canCancelProcessing else { return }
        instantBatch?.progress.isCancelled = true
        statusMessage = "Stopping after this image…"
    }

    func beginBatch(of count: Int, isWatched: Bool) -> UUID {
        observeActivationIfNeeded()
        let batch: ActiveBatch
        if isWatched {
            if var running = watchBurst {
                // A retried arrival joins the burst in progress.
                running.progress.add(count)
                running.runs += 1
                watchBurst = running
                batch = running
            } else {
                batch = ActiveBatch(progress: ProcessingBatch(total: count), recipeName: batchRecipeName, isWatched: true)
                watchBurst = batch
            }
        } else if var running = instantBatch, !running.progress.isCancelled {
            running.progress.add(count)
            running.runs += 1
            instantBatch = running
            batch = running
        } else {
            batch = ActiveBatch(progress: ProcessingBatch(total: count), recipeName: batchRecipeName, isWatched: false)
            instantBatch = batch
        }
        updateDockProgress()
        return batch.id
    }

    /// A cancelled drop can be replaced by a new one before its last image
    /// is done, so a batch that’s gone counts as cancelled too.
    func isBatchCancelled(_ id: UUID) -> Bool {
        if watchBurst?.id == id { return false }
        guard let instantBatch, instantBatch.id == id else { return true }
        return instantBatch.progress.isCancelled
    }

    func recordBatchResult(_ id: UUID, output: URL?) {
        updateBatch(id) { batch in
            if let output {
                batch.progress.recordSuccess(output: output)
            } else {
                batch.progress.recordFailure()
            }
        }
        if output != nil, !NSApp.isActive {
            backgroundFinishedCount += 1
            DockTile.setBadge(backgroundFinishedCount)
        }
        updateDockProgress()
    }

    func endBatchRun(_ id: UUID) {
        var finished: ActiveBatch?
        updateBatch(id) { batch in
            batch.runs -= 1
            if batch.runs <= 0 { finished = batch }
        }
        guard let finished else { return }
        if finished.isWatched {
            watchBurst = nil
        } else {
            instantBatch = nil
        }
        updateDockProgress()

        let progress = finished.progress
        if progress.isCancelled {
            statusMessage = "Cancelled after \(progress.completed) of \(progress.total)"
        }
        if !NSApp.isActive, progress.completed > 0 {
            let title: String
            if finished.isWatched {
                title = watchedInputFolder.map { "Watched Folder “\($0.lastPathComponent)”" } ?? "Watched Folder"
            } else {
                title = progress.isCancelled ? "Processing Cancelled" : "Processing Finished"
            }
            ProcessingNotifier.shared.post(
                title: title,
                body: progress.summary(recipeName: finished.recipeName),
                revealing: progress.outputs
            )
        }
    }

    /// The recipe named in a batch’s summary; an unsaved look has no name to give.
    private var batchRecipeName: String? {
        isRecipeModified ? nil : currentRecipe.name
    }

    private func updateBatch(_ id: UUID, _ change: (inout ActiveBatch) -> Void) {
        if var batch = instantBatch, batch.id == id {
            change(&batch)
            instantBatch = batch
        } else if var batch = watchBurst, batch.id == id {
            change(&batch)
            watchBurst = batch
        }
    }

    /// One bar on the Dock icon for everything in flight. A lone image finishes
    /// too quickly for a bar to mean anything.
    private func updateDockProgress() {
        let batches = [instantBatch, watchBurst].compactMap(\.self)
        let total = batches.reduce(0) { $0 + $1.progress.total }
        let completed = batches.reduce(0) { $0 + $1.progress.completed }
        if total > 1 {
            DockTile.showProgress(Double(completed) / Double(total))
        } else {
            DockTile.hideProgress()
        }
    }

    /// The badge counts what finished while you were away, so it clears as
    /// soon as Granular comes forward.
    private func observeActivationIfNeeded() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.backgroundFinishedCount = 0
                DockTile.setBadge(0)
            }
        }
    }
}
