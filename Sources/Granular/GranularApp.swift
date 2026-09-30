import AppKit
import GranularCore
import SwiftUI

extension Notification.Name {
    static let granularOpenURLs = Notification.Name("GranularOpenURLs")
}

final class GranularApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        ProcessingNotifier.shared.becomeDelegate()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .granularOpenURLs, object: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
            InstantCommands(model: model)
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
