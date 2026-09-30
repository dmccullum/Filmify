import AppKit

/// Progress and the finished-while-away badge on Granular’s Dock icon.
@MainActor
enum DockTile {
    private static var progressView: DockProgressView?

    static func showProgress(_ fraction: Double) {
        let tile = NSApp.dockTile
        let view = progressView ?? DockProgressView()
        view.frame = NSRect(origin: .zero, size: tile.size)
        view.fraction = min(1, max(0, fraction))
        if tile.contentView !== view {
            tile.contentView = view
            progressView = view
        }
        tile.display()
    }

    static func hideProgress() {
        guard progressView != nil else { return }
        progressView = nil
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }

    static func setBadge(_ count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }
}

/// The app icon with a progress bar set into its foot, drawn like the EXP
/// counter on the camera back: a dark window lit from within in amber.
private final class DockProgressView: NSView {
    var fraction = 0.0

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)

        let width = bounds.width * 0.72
        let height = max(6, bounds.height * 0.1)
        let track = NSRect(
            x: bounds.midX - width / 2,
            y: bounds.height * 0.1,
            width: width,
            height: height
        )
        let radius = height / 2

        // The window, with a lit lower edge where it's cut into the metal.
        NSColor.white.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: track.offsetBy(dx: 0, dy: -1), xRadius: radius, yRadius: radius).fill()
        NSColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard fraction > 0 else { return }
        let inset = track.insetBy(dx: 1.5, dy: 1.5)
        let lit = NSRect(
            x: inset.minX,
            y: inset.minY,
            width: max(inset.height, inset.width * fraction),
            height: inset.height
        )
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        let amber = NSColor(srgbRed: 1, green: 0x8A / 255, blue: 0x3D / 255, alpha: 1)
        glow.shadowColor = amber.withAlphaComponent(0.7)
        glow.shadowBlurRadius = height * 0.6
        glow.shadowOffset = .zero
        glow.set()
        amber.setFill()
        NSBezierPath(roundedRect: lit, xRadius: inset.height / 2, yRadius: inset.height / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
