import AppKit

/// Granular’s menu bar icon: a 35 mm film canister with its leader out, drawn
/// as a template so the menu bar tints it for light, dark and tinted menu bars.
/// The canister fills in while a watched folder is being watched.
@MainActor
enum MenuBarGlyph {
    static func image(isWatching: Bool) -> NSImage {
        isWatching ? filled : outlined
    }

    private static let outlined = makeImage(filled: false)
    private static let filled = makeImage(filled: true)

    /// Drawn on whole and half points so every edge lands on the pixel grid
    /// of a Retina menu bar, with the leader as the same weight in both states.
    private static func makeImage(filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            NSColor.black.set()

            // The spool’s ends, above and below the tin.
            NSBezierPath(roundedRect: NSRect(x: 4.5, y: 13, width: 3, height: 2.5), xRadius: 0.75, yRadius: 0.75).fill()
            NSBezierPath(roundedRect: NSRect(x: 5, y: 0.5, width: 2, height: 1.5), xRadius: 0.5, yRadius: 0.5).fill()

            // The tin, with its end caps a little proud of the body.
            for y in [2.0, 11.5] {
                NSBezierPath(roundedRect: NSRect(x: 1, y: y, width: 10, height: 1.5), xRadius: 0.5, yRadius: 0.5).fill()
            }
            if filled {
                NSRect(x: 1.5, y: 3, width: 9, height: 9).fill()
            } else {
                NSRect(x: 1.5, y: 3, width: 1, height: 9).fill()
                NSRect(x: 9.5, y: 3, width: 1, height: 9).fill()
            }

            // The leader, cut down to its tongue the way film leaves the box.
            let leader = NSBezierPath()
            leader.move(to: NSPoint(x: 10, y: 3.5))
            leader.line(to: NSPoint(x: 15.5, y: 3.5))
            leader.appendArc(
                withCenter: NSPoint(x: 15.5, y: 5.25),
                radius: 1.75,
                startAngle: -90,
                endAngle: 90
            )
            leader.line(to: NSPoint(x: 14.5, y: 7))
            leader.curve(
                to: NSPoint(x: 11.5, y: 10),
                controlPoint1: NSPoint(x: 12.75, y: 7),
                controlPoint2: NSPoint(x: 12.75, y: 10)
            )
            leader.line(to: NSPoint(x: 10, y: 10))
            leader.close()
            leader.fill()

            // Sprocket holes punched through the leader.
            NSGraphicsContext.current?.compositingOperation = .clear
            for x in [12.5, 15] {
                NSBezierPath(rect: NSRect(x: x, y: 4.5, width: 1.5, height: 1)).fill()
            }
            if filled {
                // A gap where the leader leaves the tin, so the two still read apart.
                NSBezierPath(rect: NSRect(x: 11, y: 3.5, width: 0.5, height: 6.5)).fill()
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Granular"
        return image
    }
}
