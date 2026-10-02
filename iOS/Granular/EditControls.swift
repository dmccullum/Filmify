import GranularCore
import SwiftUI

// MARK: - Tools

/// One effect in the tool bar under the photo: yellow while it's the one
/// being adjusted, white while it's on, and faint while it's off.
struct ToolTab: View {
    static let width: CGFloat = 28

    let effect: EditEffect
    let isSelected: Bool
    let isEnabled: Bool
    let isModified: Bool
    let action: () -> Void

    private var accessibilityState: String {
        guard effect.isToggleable else { return isModified ? "Edited" : "" }
        return isEnabled ? (isModified ? "On, edited" : "On") : "Off"
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: effect.symbol)
                    .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                    .frame(height: 26)
                // Marks a tool that's been changed from the recipe.
                Circle()
                    .frame(width: 4, height: 4)
                    .opacity(isModified ? 1 : 0)
            }
            .foregroundStyle(style)
            .frame(width: ToolTab.width, height: 44)
            // Reaches past the glyph, so the row is easy to hit end to end.
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .padding(.horizontal, -6)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: isSelected)
        .animation(.smooth(duration: 0.25), value: isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(effect.title)
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var style: Color {
        switch (isSelected, isEnabled) {
        case (true, true): .editSelection
        case (true, false): .editSelection.opacity(0.5)
        case (false, true): .white
        case (false, false): .white.opacity(0.3)
        }
    }
}

extension Color {
    /// The one color in Edit, as in Photos: the tool being adjusted.
    static let editSelection = Color(.systemYellow)
}

// MARK: - Sliders

/// One adjustment on a single line: its name, a slider and its value.
/// Double-tapping anywhere along it puts back the recipe's own value.
struct ParameterSlider: View {
    let parameter: EffectParameter
    @Binding var value: Double
    /// The recipe's own value.
    let recipeValue: Double
    /// Called as a drag begins, before the first change, and as it ends.
    var onEditing: (Bool) -> Void = { _ in }

    static let height: CGFloat = 44

    @State private var isTracking = false
    @State private var resetsOnRelease = false

    var body: some View {
        HStack(spacing: 12) {
            Text(parameter.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 80, alignment: .leading)
                .accessibilityHidden(true)

            Slider(value: $value, in: parameter.range) { editing in
                isTracking = editing
                onEditing(editing)
                // The slider sets its own value as the touch lifts, so a
                // double-tap on it resets only after that.
                if !editing, resetsOnRelease {
                    resetsOnRelease = false
                    DispatchQueue.main.async { reset() }
                }
            }
            .accessibilityLabel(parameter.title)
            .accessibilityValue(parameter.display.accessibilityText(for: value))
            .accessibilityAction(named: "Reset to Recipe Value") { value = recipeValue }

            Text(parameter.display.text(for: value))
                .monospacedDigit()
                .foregroundStyle(value == recipeValue ? .secondary : .primary)
                .frame(width: 50, alignment: .trailing)
                .contentTransition(.numericText(value: value))
                .animation(.snappy(duration: 0.15), value: value)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
        .frame(height: Self.height)
        .contentShape(Rectangle())
        // Alongside the slider's own drag, so it reaches the track too.
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if isTracking { resetsOnRelease = true } else { reset() }
        })
        // A light tap as the slider passes the recipe's own value.
        .sensoryFeedback(trigger: value) { old, new in
            (old - recipeValue).sign != (new - recipeValue).sign || new == recipeValue ? .selection : nil
        }
    }

    private func reset() {
        withAnimation(.smooth) { value = recipeValue }
    }
}

// MARK: - Film stocks

/// Every film stock as a thumbnail of the photo, in a strip that scrolls.
struct StockStrip: View {
    @Binding var stock: FilmStockID
    let thumbnails: [FilmStockID: CGImage]

    private static let order = [FilmStockID.none] + FilmStockFamily.allCases.flatMap(\.stocks)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Self.order, id: \.self) { candidate in
                        StockTile(
                            stock: candidate,
                            thumbnail: thumbnails[candidate],
                            isSelected: candidate == stock
                        ) {
                            stock = candidate
                        }
                        .id(candidate)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(stock, anchor: .center) }
            .onChange(of: stock) { _, stock in
                withAnimation(.smooth) { proxy.scrollTo(stock, anchor: .center) }
            }
        }
        .sensoryFeedback(.selection, trigger: stock)
    }
}

private struct StockTile: View {
    static let width: CGFloat = 52

    let stock: FilmStockID
    let thumbnail: CGImage?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 3) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
                .frame(width: StockTile.width, height: StockTile.width)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white, lineWidth: 2)
                        .opacity(isSelected ? 1 : 0)
                }
                .animation(.easeOut(duration: 0.2), value: thumbnail != nil)

                Text(stock.shortName)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: StockTile.width)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stock.name)
        .accessibilityHint(stock.vibe)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension FilmStockID {
    /// The name under a stock's thumbnail, short enough to fit it.
    var shortName: String {
        switch self {
        case .none: "None"
        case .portra400: "Portra"
        case .ektar100: "Ektar"
        case .gold200: "Gold"
        case .pro400H: "Pro"
        case .superia400: "Superia"
        case .vision250D: "250D"
        case .vision500T: "500T"
        case .eterna500: "Eterna"
        case .optima100: "Optima"
        case .velvia100F: "Velvia"
        case .eliteChrome: "Elite"
        case .e100G: "E100G"
        case .e200: "E200"
        case .kodachrome64: "Chrome"
        case .instax: "Instax"
        case .fp100C: "FP100"
        case .triX400: "Tri-X"
        case .hp5: "HP5+"
        }
    }
}

// MARK: - Backdrop

/// A plain blur of what's behind, lighter than a material and with none of
/// its grey: over black it stays black.
struct BackdropBlur: UIViewRepresentable {
    /// From 0, no blur, to 1, the system's full dark blur.
    let intensity: CGFloat

    func makeUIView(context: Context) -> BackdropBlurView {
        BackdropBlurView()
    }

    func updateUIView(_ view: BackdropBlurView, context: Context) {
        view.intensity = intensity
    }
}

final class BackdropBlurView: UIVisualEffectView {
    private var animator: UIViewPropertyAnimator?

    var intensity: CGFloat = 1 {
        didSet { if intensity != oldValue { animator?.fractionComplete = intensity } }
    }

    init() {
        super.init(effect: nil)
        isUserInteractionEnabled = false
        // Sets the blur back up whenever the app returns, which ends any
        // animator held paused.
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuild),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { rebuild() } else { tearDown() }
    }

    /// A blur stopped part-way through fading in is the only public way to
    /// one lighter than the system's.
    @objc private func rebuild() {
        tearDown()
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
            self?.effect = UIBlurEffect(style: .dark)
        }
        animator.pausesOnCompletion = true
        animator.fractionComplete = intensity
        self.animator = animator
    }

    private func tearDown() {
        guard let animator else { return }
        animator.stopAnimation(true)
        self.animator = nil
        effect = nil
    }

    deinit {
        animator?.stopAnimation(true)
    }
}
