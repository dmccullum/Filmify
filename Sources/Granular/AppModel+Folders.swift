import AppKit
import GranularCore
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// Watched folders, security-scoped bookmarks and launch at login.
extension AppModel {
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

    func chooseFolder(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    @discardableResult
    func setFolder(_ url: URL, key: String, assignment: (URL) -> Void) -> Bool {
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

    func watchingFailed(_ message: String) {
        guard isWatching else { return }
        monitor = nil
        isWatching = false
        watchErrorMessage = message
        watchStatusMessage = message
        statusMessage = message
    }

    func restoreFolder(forKey key: String, assignment: (URL) -> Void) {
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

    func retainSecurityScope(for url: URL) {
        guard !activeSecurityURLs.contains(url) else { return }
        if url.startAccessingSecurityScopedResource() {
            activeSecurityURLs.append(url)
        }
    }
}

enum BookmarkKey {
    static let dropOutput = "folders.dropOutput"
    static let watchInput = "folders.watchInput"
    static let watchOutput = "folders.watchOutput"
}
