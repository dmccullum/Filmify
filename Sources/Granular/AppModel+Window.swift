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
        UserDefaults.standard.set(operationMode.rawValue, forKey: SettingsKey.lastMode)
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

    /// The Granular window, not Settings, a panel or a sheet, even when one of
    /// those has focus.
    var mainWindow: NSWindow? {
        func isMain(_ window: NSWindow) -> Bool {
            window.isVisible && window.canBecomeMain && !(window is NSPanel)
                && window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") != true
                && !isRecipeLibraryWindow(window)
        }
        if let key = NSApplication.shared.keyWindow, isMain(key) { return key }
        return NSApplication.shared.windows.first(where: isMain)
    }

    private static let defaultContentSizes: [OperationMode: NSSize] = [
        .drop: NSSize(width: 700, height: 400),
        .edit: NSSize(width: 1_080, height: 970)
    ]

    /// The smallest a mode’s window may be. Instant keeps a fixed height.
    private static func minimumContentSize(for mode: OperationMode) -> NSSize {
        switch mode {
        case .drop: NSSize(width: 620, height: defaultContentSizes[.drop]!.height)
        case .edit: NSSize(width: 620, height: 340)
        }
    }

    /// Where the window goes for a mode: the frame it had the last time the
    /// user left it there, if that place still exists, otherwise the mode’s
    /// default size around the window’s current top centre. Either way it is
    /// kept on screen.
    func targetFrame(for mode: OperationMode, in window: NSWindow) -> NSRect {
        let defaultSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: Self.defaultContentSizes[mode]!)
        ).size
        var frame: NSRect
        var visible: NSRect

        if let saved = savedWindowFrames[mode],
           let home = WindowFrameMath.bestVisibleFrame(for: saved, in: NSScreen.screens.map(\.visibleFrame)) {
            frame = saved
            visible = home
            if mode == .drop {
                // Only Instant’s width and place are remembered; its height is fixed.
                frame.size.height = defaultSize.height
                frame.origin.y = saved.maxY - defaultSize.height
            }
        } else {
            let current = window.frame
            frame = NSRect(
                x: current.midX - defaultSize.width / 2,
                y: current.maxY - defaultSize.height,
                width: defaultSize.width,
                height: defaultSize.height
            )
            visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? current
        }

        let minimumSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize(for: mode))
        ).size
        return WindowFrameMath.clamped(frame, to: visible, minimumSize: minimumSize)
    }

    /// The area below the toolbar that a mode's content gets at its window size.
    func layoutSize(for mode: OperationMode) -> CGSize? {
        guard let window = mainWindow, let contentView = window.contentView else { return nil }
        let toolbarHeight = contentView.bounds.height - window.contentLayoutRect.height
        let size = window.contentRect(forFrameRect: targetFrame(for: mode, in: window)).size
        return CGSize(width: size.width, height: size.height - toolbarHeight)
    }

    /// The size the window first opens at, so a remembered window doesn’t
    /// open small and then jump.
    var initialWindowSize: CGSize {
        let mode = operationMode
        guard let saved = savedWindowFrames[mode] else { return Self.defaultContentSizes[mode]!.cgSize }
        let height = mode == .drop ? Self.defaultContentSizes[.drop]!.height : saved.height
        return CGSize(width: max(saved.width, 620), height: height)
    }

    func resizeWindow(for mode: OperationMode, animated: Bool) async {
        guard let window = mainWindow else { return }
        let targetFrame = targetFrame(for: mode, in: window)
        let contentHeight = window.contentRect(forFrameRect: targetFrame).height

        // Instant mode keeps a fixed height and a free width. Lift the limit
        // before growing into Edit mode; apply it once the window has shrunk.
        if mode == .edit {
            applySizeLimits(for: mode, contentHeight: contentHeight, to: window)
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
            applySizeLimits(for: mode, contentHeight: contentHeight, to: window)
        }

        // The window now sits where this mode remembers it. From here on,
        // wherever the user leaves it is what gets remembered.
        guard operationMode == mode else { return }
        savedWindowFrames[mode] = window.frame
        scheduleSavingWindowFrames()
        observeFrameChanges(of: window)
    }

    /// Follows the window as the user moves and resizes it, remembering its
    /// frame for the current mode. Frames during a mode switch are ignored:
    /// the transition records where it ends up.
    private func observeFrameChanges(of window: NSWindow) {
        guard windowFrameObservers.isEmpty || observedWindow !== window else { return }
        windowFrameObservers.forEach { NotificationCenter.default.removeObserver($0) }
        observedWindow = window

        let center = NotificationCenter.default
        let track: @Sendable (Notification) -> Void = { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window else { return }
                self.windowFrameDidChange(window)
            }
        }
        windowFrameObservers = [
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main, using: track),
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: track),
            center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.persistWindowFrames() }
            }
        ]
    }

    private func windowFrameDidChange(_ window: NSWindow) {
        guard !isSettlingWindow, !window.styleMask.contains(.fullScreen), !window.isMiniaturized else { return }
        savedWindowFrames[operationMode] = window.frame
        scheduleSavingWindowFrames()
    }

    private func scheduleSavingWindowFrames() {
        windowFrameSaveTask?.cancel()
        windowFrameSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.persistWindowFrames()
        }
    }

    func persistWindowFrames() {
        for (mode, frame) in savedWindowFrames {
            UserDefaults.standard.set(
                [frame.minX, frame.minY, frame.width, frame.height].map(Double.init),
                forKey: SettingsKey.windowFrame(mode)
            )
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

private extension NSSize {
    var cgSize: CGSize { CGSize(width: width, height: height) }
}
