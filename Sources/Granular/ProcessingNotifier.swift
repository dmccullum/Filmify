import AppKit
import UserNotifications

/// Posts one summary when a batch or a watched-folder burst finishes while
/// Granular is in the background. Clicking it reveals what was made.
@MainActor
final class ProcessingNotifier: NSObject {
    static let shared = ProcessingNotifier()

    private nonisolated static let outputsKey = "outputs"

    /// Notification Center only serves a bundled app; a bare `swift run`
    /// binary has no identity to post under.
    private var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Takes clicks on notifications, including one that relaunches Granular,
    /// so this is set as the app finishes launching. It asks for nothing.
    func becomeDelegate() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks for permission the first time there’s something to say, not at launch.
    func post(title: String, body: String, revealing outputs: [URL]) {
        guard isAvailable else { return }
        becomeDelegate()
        let paths = outputs.map(\.path)
        Task {
            let center = UNUserNotificationCenter.current()
            switch await center.notificationSettings().authorizationStatus {
            case .notDetermined:
                guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            case .denied:
                return
            default:
                break
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.userInfo = [Self.outputsKey: paths]
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    fileprivate func reveal(_ paths: [String]) {
        NSApp.activate()
        let urls = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

extension ProcessingNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let paths = response.notification.request.content.userInfo[Self.outputsKey] as? [String] ?? []
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in
                ProcessingNotifier.shared.reveal(paths)
            }
        }
        completionHandler()
    }

    /// Granular only posts from the background, but if it has come forward
    /// by the time the summary lands, still show it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
