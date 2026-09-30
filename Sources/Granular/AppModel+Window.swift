import AppKit
import GranularCore
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// Window sizing and the Instant/Edit mode transition.
extension AppModel {
    func modeDidChange() {
        if operationMode == .drop, jobs.isEmpty {
            statusMessage = "Ready"
        }
        scheduleWindowResize(for: operationMode, animated: true)
    }

    func scheduleWindowResize(for mode: OperationMode, animated: Bool = true) {
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            guard !Task.isCancelled, let self, self.operationMode == mode else { return }
            if mode == .drop {
                // The film loads alongside the resize, not after it.
                self.isFilmLoaded = true
            }
            await self.resizeWindow(for: mode, animated: animated)
            guard !Task.isCancelled, self.operationMode == mode else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                self.isSettlingWindow = false
                self.arrivingLayoutSize = nil
            }
        }
    }

    var mainWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
    }

    func targetContentSize(for mode: OperationMode, in window: NSWindow) -> NSSize {
        var contentSize = mode == .drop
            ? NSSize(width: 700, height: 400)
            : NSSize(width: 1_080, height: 970)
        if let visibleFrame = window.screen?.visibleFrame {
            contentSize.height = min(contentSize.height, visibleFrame.height - 28)
        }
        return contentSize
    }

    /// The area below the toolbar that a mode's content gets at its window size.
    func layoutSize(for mode: OperationMode) -> CGSize? {
        guard let window = mainWindow, let contentView = window.contentView else { return nil }
        let toolbarHeight = contentView.bounds.height - window.contentLayoutRect.height
        let size = targetContentSize(for: mode, in: window)
        return CGSize(width: size.width, height: size.height - toolbarHeight)
    }

    func resizeWindow(for mode: OperationMode, animated: Bool) async {
        guard let window = mainWindow else { return }
        let contentSize = targetContentSize(for: mode, in: window)
        let targetFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        var targetFrame = window.frame
        targetFrame.origin.x = window.frame.midX - targetFrameSize.width / 2
        targetFrame.origin.y = window.frame.maxY - targetFrameSize.height
        targetFrame.size = targetFrameSize

        if let visibleFrame = window.screen?.visibleFrame {
            targetFrame.origin.x = min(
                max(targetFrame.origin.x, visibleFrame.minX),
                visibleFrame.maxX - targetFrame.width
            )
            targetFrame.origin.y = min(
                max(targetFrame.origin.y, visibleFrame.minY),
                visibleFrame.maxY - targetFrame.height
            )
        }

        // Instant mode keeps a fixed height and a free width. Lift the limit
        // before growing into Edit mode; apply it once the window has shrunk.
        if mode == .edit {
            applySizeLimits(for: mode, contentHeight: contentSize.height, to: window)
        }
        if animated {
            // Animate through the window's animator rather than the blocking
            // setFrame(animate:), so SwiftUI keeps drawing while the size changes.
            await withCheckedContinuation { continuation in
                NSAnimationContext.runAnimationGroup { context in
                    let c = Self.modeTransitionCurve
                    context.duration = Self.modeTransitionDuration
                    context.timingFunction = CAMediaTimingFunction(
                        controlPoints: Float(c.x1), Float(c.y1), Float(c.x2), Float(c.y2)
                    )
                    window.animator().setFrame(targetFrame, display: true)
                } completionHandler: {
                    continuation.resume()
                }
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
        if mode == .drop {
            applySizeLimits(for: mode, contentHeight: contentSize.height, to: window)
        }
    }

    func applySizeLimits(for mode: OperationMode, contentHeight: CGFloat, to window: NSWindow) {
        let unlimited = CGFloat.greatestFiniteMagnitude
        switch mode {
        case .drop:
            window.contentMinSize = NSSize(width: 620, height: contentHeight)
            window.contentMaxSize = NSSize(width: unlimited, height: contentHeight)
        case .edit:
            window.contentMinSize = NSSize(width: 620, height: 340)
            window.contentMaxSize = NSSize(width: unlimited, height: unlimited)
        }
    }
}
