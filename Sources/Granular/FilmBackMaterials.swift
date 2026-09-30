import SwiftUI

// Surfaces for the Instant-mode "camera back": the alloy body for the chrome,
// and the printed tin / paper of the film canisters that stand in for recipes.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum FilmBackPalette {
    static let signal = Color(hex: 0xE2471B)
    static let counter = Color(hex: 0xFF8A3D)
    static let ink = Color(hex: 0x141414)
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The camera body: bead-blasted aluminum in light appearance, dark
/// magnesium in dark. A fine, even grain rather than a brushed direction.
struct AlloySurface: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [Color(hex: 0x1B1C1E), Color(hex: 0x131415), Color(hex: 0x0D0E0F)]
                    : [Color(hex: 0xDCDEE0), Color(hex: 0xCDD0D3), Color(hex: 0xBFC2C6)],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(decorative: AlloyGrain.tile, scale: 2)
                .resizable(resizingMode: .tile)
                .opacity(isDark ? 0.45 : 0.8)
            // A soft, broad sheen, as on a satin-finished casting.
            RadialGradient(
                colors: [.white.opacity(isDark ? 0.04 : 0.22), .white.opacity(0)],
                center: UnitPoint(x: 0.3, y: 0),
                startRadius: 0,
                endRadius: 520
            )
        }
        .allowsHitTesting(false)
    }
}

/// A seeded tile of fine light and dark specks for the blasted-metal grain.
@MainActor
private enum AlloyGrain {
    static let tile: CGImage = {
        let size = 192
        var rng = SeededGenerator(seed: 23)
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for index in 0..<(size * size) {
            let light = Bool.random(using: &rng)
            let alpha = Int.random(in: 0...34, using: &rng)
            let value = light ? alpha : 0
            pixels[index * 4] = UInt8(value)
            pixels[index * 4 + 1] = UInt8(value)
            pixels[index * 4 + 2] = UInt8(value)
            pixels[index * 4 + 3] = UInt8(alpha)
        }
        let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }()
}

extension View {
    /// Text stamped into the metal.
    func engraved() -> some View {
        modifier(EngravedText())
    }
}

private struct EngravedText: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
                .foregroundStyle(Color(hex: 0xC9CDD0))
                .shadow(color: .black.opacity(0.7), radius: 0, y: -1)
        } else {
            content
                .foregroundStyle(Color(hex: 0x3F4347))
                .shadow(color: .white.opacity(0.85), radius: 0, y: 1)
        }
    }
}

/// The dark window the counters read through, lit along its lower lip.
struct CounterWindow: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(hex: 0x0D0D0D))
            .shadow(color: .white.opacity(0.7), radius: 0, y: 1)
    }
}

// MARK: - Canister pieces

struct CylinderShade: View {
    var strength: Double = 1

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.48 * strength), location: 0),
                .init(color: .black.opacity(0.18 * strength), location: 0.06),
                .init(color: .white.opacity(0.10 * strength), location: 0.15),
                .init(color: .white.opacity(0.20 * strength), location: 0.21),
                .init(color: .white.opacity(0.06 * strength), location: 0.3),
                .init(color: .white.opacity(0), location: 0.42),
                .init(color: .black.opacity(0.08 * strength), location: 0.66),
                .init(color: .black.opacity(0.28 * strength), location: 0.86),
                .init(color: .black.opacity(0.5 * strength), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .allowsHitTesting(false)
    }
}

struct HazardStripes: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xFFD21F)))
            let pitch: CGFloat = 12
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                path.addLine(to: CGPoint(x: x + size.height + pitch / 2, y: 0))
                path.addLine(to: CGPoint(x: x + pitch / 2, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(FilmBackPalette.ink))
                x += pitch
            }
        }
    }
}

/// Lays a rotated child out in its rotated footprint.
struct VerticalLabel: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(.unspecified)
        return CGSize(width: size.height, height: size.width)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(child.sizeThatFits(.unspecified))
        )
    }
}

/// The maker's nameplate on the camera's top plate: spaced condensed
/// capitals in the website's Barlow Condensed, painted white on black
/// chrome and black on stainless.
struct CameraNameplate: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        Text("GRANULAR")
            .font(.custom("BarlowCondensed-SemiBold", size: 21))
            .tracking(4.5)
            .foregroundStyle(
                LinearGradient(
                    colors: isDark
                        ? [Color(hex: 0xFFFFFF), Color(hex: 0xD6D9DC)]
                        : [Color(hex: 0x1A1B1C), Color(hex: 0x3A3C3E)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: isDark ? .black.opacity(0.8) : .white.opacity(0.9), radius: 0, y: isDark ? -1 : 1)
            .fixedSize()
            .accessibilityLabel("Granular")
            .accessibilityAddTraits(.isHeader)
    }
}
