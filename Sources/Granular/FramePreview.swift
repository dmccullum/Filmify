import AppKit
import Quartz

/// A frame on the strip as Quick Look sees it.
struct PreviewFrame: Equatable {
    let id: UUID
    let url: URL
    let image: CGImage?
}

/// Quick Look for the selected frame on the film strip. Space opens the
/// panel, and while it’s open the arrow keys step along the strip, as in Finder.
@MainActor
final class FramePreviewController: NSResponder {
    static let shared = FramePreviewController()

    /// The frames on the strip, nearest the gate first.
    var frames: [PreviewFrame] = [] {
        didSet {
            guard frames != oldValue, isPanelVisible else { return }
            QLPreviewPanel.shared().reloadData()
        }
    }
    /// Where each frame sits in its window, top-left origin, for the zoom in and out.
    var frameRects: [UUID: CGRect] = [:]

    private var roll: FilmRoll { .shared }

    var isPanelVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    private var selectedFrame: PreviewFrame? {
        frames.first { $0.id == roll.selectedFrameID }
    }

    func togglePanel() {
        if isPanelVisible {
            QLPreviewPanel.shared().orderOut(nil)
        } else if selectedFrame != nil {
            joinResponderChain()
            QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
        }
    }

    /// Call when the strip’s selection changes, so an open panel follows it.
    func selectionDidChange() {
        guard isPanelVisible else { return }
        if selectedFrame == nil {
            QLPreviewPanel.shared().orderOut(nil)
        } else {
            QLPreviewPanel.shared().reloadData()
        }
    }

    /// Moves the selection one frame along the strip; negative is toward the gate.
    func moveSelection(by offset: Int) {
        guard !frames.isEmpty else { return }
        let current = frames.firstIndex { $0.id == roll.selectedFrameID }
        let index = current.map { min(frames.count - 1, max(0, $0 + offset)) } ?? 0
        roll.selectedFrameID = frames[index].id
        selectionDidChange()
    }

    /// Quick Look looks for its controller along the key window’s responder
    /// chain. SwiftUI owns the views, so the controller rides just past the window.
    private func joinResponderChain() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        var responder: NSResponder? = window
        while let current = responder {
            if current === self { return }
            responder = current.nextResponder
        }
        nextResponder = window.nextResponder
        window.nextResponder = self
    }

    // Quick Look calls these on the main thread, though they're declared on NSObject.
    override nonisolated func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { selectedFrame != nil }
    }

    override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}

    fileprivate func screenRect(for id: UUID) -> NSRect {
        guard let rect = frameRects[id],
              let window = NSApp.mainWindow,
              let contentView = window.contentView else { return .zero }
        let inWindow = NSRect(
            x: rect.minX,
            y: contentView.bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        return window.convertToScreen(inWindow)
    }
}

extension FramePreviewController: @MainActor QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        selectedFrame == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        selectedFrame?.url as NSURL?
    }
}

extension FramePreviewController: @MainActor QLPreviewPanelDelegate {
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        switch event.specialKey {
        case .leftArrow?:
            moveSelection(by: -1)
            return true
        case .rightArrow?:
            moveSelection(by: 1)
            return true
        default:
            return false
        }
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        guard let selectedFrame else { return .zero }
        return screenRect(for: selectedFrame.id)
    }

    func previewPanel(
        _ panel: QLPreviewPanel!,
        transitionImageFor item: (any QLPreviewItem)!,
        contentRect: UnsafeMutablePointer<NSRect>!
    ) -> Any! {
        guard let image = selectedFrame?.image else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
}
