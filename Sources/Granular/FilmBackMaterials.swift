import SwiftUI

// Surfaces for the Instant-mode "camera back": brushed steel for the chrome,
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

/// Stainless steel in light appearance, black chrome in dark.
struct BrushedSteel: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [Color(hex: 0x4A4D50), Color(hex: 0x36393B), Color(hex: 0x2A2C2E)]
                    : [Color(hex: 0xE9EBEC), Color(hex: 0xD1D4D6), Color(hex: 0xBDC1C4)],
                startPoint: .top,
                endPoint: .bottom
            )
            Canvas { context, size in
                var rng = SeededGenerator(seed: 11)
                var y: CGFloat = 0
                while y < size.height {
                    let height = CGFloat.random(in: 0.4...1.1, using: &rng)
                    var x: CGFloat = -40
                    while x < size.width {
                        let length = CGFloat.random(in: 60...420, using: &rng)
                        let light = Bool.random(using: &rng)
                        let opacity = Double.random(in: 0.025...0.09, using: &rng)
                        context.fill(
                            Path(CGRect(x: x, y: y, width: length, height: height)),
                            with: .color(light ? .white.opacity(opacity) : .black.opacity(opacity * 0.7))
                        )
                        x += length + CGFloat.random(in: 0...30, using: &rng)
                    }
                    y += height + CGFloat.random(in: 0.2...1.4, using: &rng)
                }
            }
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(isDark ? 0.10 : 0.30), location: 0.3),
                    .init(color: .white.opacity(0), location: 0.47),
                    .init(color: .white.opacity(isDark ? 0.05 : 0.14), location: 0.7),
                    .init(color: .white.opacity(0), location: 0.86)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Text stamped into the steel.
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

struct SteelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(FilmBackPalette.signal)
                .frame(width: 6, height: 6)
                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
            configuration.label
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(Color(hex: 0x1C1C1E))
        .padding(.horizontal, 13)
        .frame(height: 26)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [Color(hex: 0xF5F6F7), Color(hex: 0xD3D6D8), Color(hex: 0xB7BBBE)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 0.5).padding(0.5))
        .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
        .brightness(configuration.isPressed ? -0.08 : 0)
        .contentShape(Capsule())
    }
}

// MARK: - Canister pieces

struct CylinderShade: View {
    var strength: Double = 1

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.50 * strength), location: 0),
                .init(color: .black.opacity(0.12 * strength), location: 0.09),
                .init(color: .white.opacity(0.42 * strength), location: 0.23),
                .init(color: .white.opacity(0), location: 0.42),
                .init(color: .black.opacity(0.06 * strength), location: 0.68),
                .init(color: .black.opacity(0.55 * strength), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .allowsHitTesting(false)
    }
}

struct Ribbed: View {
    var dark: Color
    var light: Color
    var pitch: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark))
            var x: CGFloat = 0
            while x < size.width {
                context.fill(
                    Path(CGRect(x: x + pitch * 0.55, y: 0, width: pitch * 0.45, height: size.height)),
                    with: .color(light)
                )
                x += pitch
            }
        }
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

/// The maker's nameplate on the camera's top plate: spaced mid-century
/// capitals, painted white on black chrome and black on stainless.
struct CameraNameplate: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        Text("GRANULAR")
            .font(.custom("Futura-Medium", size: 16))
            .tracking(5)
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
