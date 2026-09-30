import Foundation
import UniformTypeIdentifiers

public actor WatchedFolderMonitor {
    private struct Fingerprint: Hashable {
        let size: Int
        let modificationDate: Date
    }

    private struct Candidate {
        var fingerprint: Fingerprint
        var stablePasses: Int
        var retryAfter: ContinuousClock.Instant?
    }

    private enum ScanError: LocalizedError {
        case folderUnavailable(URL)
        case folderUnreadable(URL, String)

        var errorDescription: String? {
            switch self {
            case let .folderUnavailable(url):
                "Incoming folder “\(url.lastPathComponent)” is no longer available. Choose it again."
            case let .folderUnreadable(url, reason):
                "Granular can’t read “\(url.lastPathComponent)”: \(reason)"
            }
        }
    }

    private let scanInterval: Duration
    private let retryDelay: Duration
    private let clock = ContinuousClock()
    private var task: Task<Void, Never>?
    private var candidates: [URL: Candidate] = [:]
    private var processed: [URL: Fingerprint] = [:]
    private var lastScanError: String?

    public init() {
        scanInterval = .seconds(1)
        retryDelay = .seconds(5)
    }

    init(scanInterval: Duration, retryDelay: Duration) {
        self.scanInterval = scanInterval
        self.retryDelay = retryDelay
    }

    public func start(
        folder: URL,
        handler: @escaping @Sendable ([URL]) async -> Set<URL>,
        errorHandler: @escaping @Sendable (String) async -> Void
    ) {
        task?.cancel()
        candidates.removeAll()
        processed.removeAll()
        lastScanError = nil

        task = Task {
            while !Task.isCancelled {
                do {
                    let ready = try scan(folder: folder)
                    lastScanError = nil
                    if !ready.isEmpty {
                        let completed = await handler(ready)
                        recordResults(ready: ready, completed: completed)
                    }
                } catch {
                    let message = error.localizedDescription
                    if message != lastScanError {
                        lastScanError = message
                        await errorHandler(message)
                    }
                }

                do {
                    try await Task.sleep(for: scanInterval)
                } catch {
                    return
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func scan(folder: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ScanError.folderUnavailable(folder)
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        } catch {
            throw ScanError.folderUnreadable(folder, error.localizedDescription)
        }

        let presentURLs = Set(urls)
        candidates = candidates.filter { presentURLs.contains($0.key) }
        processed = processed.filter { presentURLs.contains($0.key) }

        var ready: [URL] = []
        for url in urls where Self.isSupportedImage(url) {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  let date = values.contentModificationDate else { continue }

            let fingerprint = Fingerprint(size: size, modificationDate: date)
            if processed[url] == fingerprint { continue }

            if var candidate = candidates[url], candidate.fingerprint == fingerprint {
                if let retryAfter = candidate.retryAfter, clock.now < retryAfter {
                    continue
                }
                candidate.retryAfter = nil
                candidate.stablePasses += 1
                candidates[url] = candidate
                if candidate.stablePasses >= 2 {
                    ready.append(url)
                }
            } else {
                candidates[url] = Candidate(
                    fingerprint: fingerprint,
                    stablePasses: 1,
                    retryAfter: nil
                )
            }
        }
        return ready
    }

    private func recordResults(ready: [URL], completed: Set<URL>) {
        for url in ready {
            guard var candidate = candidates[url] else { continue }
            if completed.contains(url) {
                processed[url] = candidate.fingerprint
                candidates.removeValue(forKey: url)
            } else {
                candidate.retryAfter = clock.now.advanced(by: retryDelay)
                candidates[url] = candidate
            }
        }
    }

    private static func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return [.jpeg, .heic, .png, .tiff, .webP, UTType("public.avif")].contains(type)
    }
}
