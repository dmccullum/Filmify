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
    func applicationWillFinishLaunching(_ notification: Notification) {
        ProcessingNotifier.shared.becomeDelegate()
        NSApp.servicesProvider = ImageServiceProvider.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        TransferFiles.removeAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TransferFiles.removeAll()
    }

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
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        SystemIntegration.connect(model)
    }

    var body: some Scene {
        @Bindable var model = model

        Window("Granular", id: "main") {
            ContentView()
                .environment(model)
                .recordingAdjustmentUndo(for: model)
        }
        .defaultSize(model.initialWindowSize)
        .restorationBehavior(.disabled)
        .commands {
            AboutCommands()
            MainWindowCommands()
            ViewerCommands(model: model)

            FileCommands(model: model)
            EditCommands(model: model)
            RecipeCommands(model: model)
            InstantCommands(model: model)
            HelpCommands()
        }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra(isInserted: Binding(
            get: { model.menuBarVisibility == .always || model.showMenuBarExtra },
            set: { model.showMenuBarExtra = $0 }
        )) {
            MenuBarStatusView()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarGlyph.image(isWatching: model.isWatching))
                .accessibilityLabel(model.isWatching ? "Granular, watching" : "Granular")
        }
        // A real menu, like every other menu bar item: keyboard navigation,
        // type-select, and it gets out of the way as soon as a choice is made.
        .menuBarExtraStyle(.menu)
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
