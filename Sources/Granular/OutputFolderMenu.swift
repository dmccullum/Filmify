import AppKit
import SwiftUI

/// The view a SwiftUI control pops an AppKit menu from.
@MainActor
final class MenuAnchor {
    weak var view: NSView?
}

struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

/// The Instant output folder’s pop-up menu: the current folder and recent
/// ones, each with its Finder icon, then Choose… and Show in Finder.
@MainActor
final class OutputFolderMenu: NSObject {
    private let model: AppModel

    private init(model: AppModel) {
        self.model = model
    }

    /// Opens like a pop-up button, with the current folder over the control.
    static func popUp(model: AppModel, from view: NSView?) {
        let controller = OutputFolderMenu(model: model)
        let menu = controller.makeMenu()
        withExtendedLifetime(controller) {
            guard let view else {
                menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                return
            }
            menu.minimumWidth = view.bounds.width
            let current = menu.items.first { $0.state == .on }
            // Line the item's icon up with the folder glyph in the footer.
            menu.popUp(positioning: current, at: NSPoint(x: -15, y: view.bounds.height), in: view)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let current = model.dropOutputFolder?.standardizedFileURL.path
        let folders = model.recentOutputFolders()
        for folder in folders {
            let item = NSMenuItem(
                title: FileManager.default.displayName(atPath: folder.path),
                action: #selector(chooseRecent(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = folder
            item.image = icon(for: folder)
            item.state = folder.standardizedFileURL.path == current ? .on : .off
            item.toolTip = folder.path(percentEncoded: false)
            menu.addItem(item)
        }
        if !folders.isEmpty {
            menu.addItem(.separator())
        }

        let choose = NSMenuItem(title: "Choose…", action: #selector(choose), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)

        let show = NSMenuItem(title: "Show in Finder", action: #selector(showInFinder), keyEquivalent: "")
        show.target = self
        show.isEnabled = model.dropOutputFolder != nil
        menu.addItem(show)
        return menu
    }

    private func icon(for folder: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: folder.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    @objc private func chooseRecent(_ item: NSMenuItem) {
        guard let folder = item.representedObject as? URL, item.state != .on else { return }
        model.useRecentDropOutputFolder(folder)
    }

    @objc private func choose() {
        // Let the menu finish closing before the open panel runs modally.
        Task { [model] in model.chooseDropOutputFolder() }
    }

    @objc private func showInFinder() {
        model.revealDropOutputFolder()
    }
}
