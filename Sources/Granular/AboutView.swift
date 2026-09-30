import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let hostingController = NSHostingController(rootView: AboutView())
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 420, height: 460)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.title = "About Granular"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // The plate moves the panel itself, so the dial keeps its drags.
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.isExcludedFromWindowsMenu = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

/// The About panel as a small plate off the camera body: the same alloy,
/// nameplate and engraving as Instant mode, with the version read off the
/// amber counters.
struct AboutView: View {
    private var info: [String: Any]? { Bundle.main.infoDictionary }
    private var version: String { info?["CFBundleShortVersionString"] as? String ?? "1.0" }
    private var build: String { info?["CFBundleVersion"] as? String ?? "1" }

    var body: some View {
        ZStack {
            AlloySurface()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 86, height: 86)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 7)
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)

                CameraNameplate()
                    .scaleEffect(1.35)
                    .padding(.vertical, 4)

                Text("A little more film in every frame.")
                    .font(.system(size: 12, weight: .medium))
                    .engraved()
                    .padding(.top, 8)

                PipelineDial()
                    .padding(.top, 18)

                HStack(spacing: 14) {
                    CounterReadout(label: "VER", value: version)
                    CounterReadout(label: "NO", value: build)
                }
                .padding(.top, 20)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Version \(version), build \(build)")

                Text("MADE WITH LOVE BY DANIEL MCCULLUM")
                    .font(.system(size: 9, weight: .bold).width(.condensed))
                    .tracking(1.8)
                    .engraved()
                    .opacity(0.8)
                    .padding(.top, 14)
            }
            .padding(.top, 18)
        }
        .frame(width: 420, height: 460)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}

/// A stamped label beside a lit counter, as on the camera back.
private struct CounterReadout: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold).width(.condensed))
                .tracking(2.4)
                .engraved()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(FilmBackPalette.counter)
                .shadow(color: FilmBackPalette.counter.opacity(0.55), radius: 4)
                .padding(.horizontal, 7)
                .frame(minWidth: 38, minHeight: 22)
                .background(CounterWindow())
        }
    }
}

/// The pipeline as a top-plate dial, after the Leica M's shutter-speed
/// dial: a knurled rim, the stages engraved round the face, and an index
/// mark on the plate. It spins under the pointer and clicks into each stop.
private struct PipelineDial: View {
    private static let stages: [(symbol: String, name: String)] = [
        ("film", "Film Tone"),
        ("camera.aperture", "Vignette"),
        ("drop.halffull", "Lens Blur"),
        ("circle.dotted", "Diffusion"),
        ("sun.horizon", "Halation"),
        ("sun.max.fill", "Landscape Glow"),
        ("aqi.medium", "Film Grain")
    ]
    private static let step = 360.0 / Double(stages.count)
    private static let diameter: CGFloat = 132

    @Environment(\.colorScheme) private var colorScheme
    /// The dial's turn in degrees, clockwise, unbounded so it spins freely.
    @State private var rotation = 0.0
    @State private var dragStart: (pointer: Double, rotation: Double)?

    /// The stage currently under the index mark.
    private var selectedIndex: Int {
        let stops = Int((-rotation / Self.step).rounded())
        let count = Self.stages.count
        return ((stops % count) + count) % count
    }

    var body: some View {
        VStack(spacing: 6) {
            IndexMark()

            ZStack {
                KnurledRim(isDark: colorScheme == .dark)
                DialFace(isDark: colorScheme == .dark)
                    .padding(9)

                ForEach(Array(Self.stages.enumerated()), id: \.offset) { index, stage in
                    Image(systemName: stage.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .engraved()
                        .opacity(index == selectedIndex ? 1 : 0.72)
                        .offset(y: -(Self.diameter / 2 - 30))
                        .rotationEffect(.degrees(Double(index) * Self.step))
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .rotationEffect(.degrees(rotation))
            .contentShape(Circle())
            .gesture(spin)

            Text(Self.stages[selectedIndex].name.uppercased())
                .font(.system(size: 9, weight: .bold).width(.condensed))
                .tracking(1.8)
                .engraved()
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: selectedIndex)
        }
        .onChange(of: selectedIndex) { _, _ in
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pipeline")
        .accessibilityValue(Self.stages[selectedIndex].name)
        .accessibilityAdjustableAction { direction in
            withAnimation(.snappy) {
                rotation += direction == .increment ? -Self.step : Self.step
            }
        }
    }

    private var spin: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let pointer = angle(of: value.location)
                if dragStart == nil {
                    dragStart = (angle(of: value.startLocation), rotation)
                }
                guard let start = dragStart else { return }
                var delta = pointer - start.pointer
                // Unwrap across the ±180° seam so a full turn keeps going.
                let turns = ((rotation - start.rotation - delta) / 360).rounded()
                delta += turns * 360
                rotation = start.rotation + delta
            }
            .onEnded { _ in
                dragStart = nil
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    rotation = (rotation / Self.step).rounded() * Self.step
                }
            }
    }

    private func angle(of point: CGPoint) -> Double {
        let radius = Self.diameter / 2
        return atan2(point.y - radius, point.x - radius) * 180 / .pi
    }
}

/// The painted line on the top plate that the dial reads against.
private struct IndexMark: View {
    var body: some View {
        Capsule()
            .fill(FilmBackPalette.signal)
            .frame(width: 3, height: 9)
            .shadow(color: FilmBackPalette.signal.opacity(0.5), radius: 2)
    }
}

/// The dial's milled edge: fine vertical ridges round a turned band.
private struct KnurledRim: View {
    let isDark: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: isDark
                            ? [Color(hex: 0x4A4D50), Color(hex: 0x232527), Color(hex: 0x55585B), Color(hex: 0x232527), Color(hex: 0x4A4D50)]
                            : [Color(hex: 0xE8EAEC), Color(hex: 0xA9ADB1), Color(hex: 0xF4F5F6), Color(hex: 0xA9ADB1), Color(hex: 0xE8EAEC)],
                        center: .center
                    )
                )
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let outer = size.width / 2
                let ridges = 96
                for ridge in 0..<ridges {
                    let theta = Double(ridge) / Double(ridges) * 2 * .pi
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + cos(theta) * (outer - 8), y: center.y + sin(theta) * (outer - 8)))
                    path.addLine(to: CGPoint(x: center.x + cos(theta) * outer, y: center.y + sin(theta) * outer))
                    context.stroke(path, with: .color(.black.opacity(isDark ? 0.6 : 0.35)), lineWidth: 1.2)
                }
            }
        }
        .shadow(color: .black.opacity(isDark ? 0.6 : 0.3), radius: 5, y: 3)
    }
}

/// The dial's top: turned metal with concentric lathe rings.
private struct DialFace: View {
    let isDark: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: isDark
                            ? [Color(hex: 0x26282A), Color(hex: 0x17181A)]
                            : [Color(hex: 0xE4E6E8), Color(hex: 0xC6C9CC)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 60
                    )
                )
            // Lathe rings catch the light as the dial turns.
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.white.opacity(0), .white.opacity(isDark ? 0.07 : 0.3), .white.opacity(0), .white.opacity(isDark ? 0.07 : 0.3), .white.opacity(0)],
                        center: .center
                    )
                )
            Circle()
                .strokeBorder(.black.opacity(isDark ? 0.5 : 0.18), lineWidth: 1)
            // A small centre boss.
            Circle()
                .fill(isDark ? Color(hex: 0x1D1E20) : Color(hex: 0xD2D5D8))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .white.opacity(isDark ? 0.08 : 0.6), radius: 0, y: 1)
        }
    }
}
