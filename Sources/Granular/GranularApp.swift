import AppKit
import GranularCore
import SwiftUI

extension Notification.Name {
    static let granularOpenURLs = Notification.Name("GranularOpenURLs")
    /// Opens one image in Edit mode, whichever mode is showing.
    static let granularOpenRecentImage = Notification.Name("GranularOpenRecentImage")
}

@MainActor
final class GranularApplicationDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .granularOpenURLs, object: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Recent images, for picking up where you left off from the Dock.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let recents = RecentImageStore.load()
        guard !recents.isEmpty else { return nil }

        let menu = NSMenu()
        for recent in recents.prefix(8) {
            let item = NSMenuItem(
                title: RecentImageStore.menuTitle(for: recent, among: recents),
                action: #selector(openRecentImage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = recent.url
            let icon = NSWorkspace.shared.icon(forFile: recent.url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openRecentImage(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL else { return }
        NSApp.activate()
        NotificationCenter.default.post(name: .granularOpenRecentImage, object: url)
    }
}

@main
struct GranularDesktopApp: App {
    @NSApplicationDelegateAdaptor(GranularApplicationDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        @Bindable var model = model

        Window("Granular", id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 700, height: 400)
        .restorationBehavior(.disabled)
        .commands {
            AboutCommands()
            MainWindowCommands()
            ViewerCommands(model: model)

            FileCommands(model: model)
            RecipeCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra(
            "Granular",
            systemImage: model.isWatching ? "drop.fill" : "drop",
            isInserted: $model.showMenuBarExtra
        ) {
            MenuBarStatusView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Granular") {
                NSApp.activate(ignoringOtherApps: true)
                AboutWindowController.shared.show()
            }
        }
    }
}
