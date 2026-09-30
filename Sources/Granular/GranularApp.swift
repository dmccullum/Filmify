import AppKit
import GranularCore
import SwiftUI

extension Notification.Name {
    static let granularOpenURLs = Notification.Name("GranularOpenURLs")
}

final class GranularApplicationDelegate: NSObject, NSApplicationDelegate {
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
        .defaultSize(model.initialWindowSize)
        .restorationBehavior(.disabled)
        .commands {
            AboutCommands()
            MainWindowCommands()
            ViewerCommands(model: model)

            FileCommands(model: model)
            RecipeCommands(model: model)
            HelpCommands()
        }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra(
            "Granular",
            systemImage: model.isWatching ? "drop.fill" : "drop",
            isInserted: Binding(
                get: { model.menuBarVisibility == .always || model.showMenuBarExtra },
                set: { model.showMenuBarExtra = $0 }
            )
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
