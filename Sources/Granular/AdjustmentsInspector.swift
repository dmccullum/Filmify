import AppKit
import GranularCore
import SwiftUI

struct AdjustmentsInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // What each card's Reset puts back, and each slider's double-click.
        let defaults = model.currentRecipe

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    // The title keeps its line; a long recipe name gives way instead.
                    Text("Adjustments")
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                    RecipeMenu()
                }

                FilmToneCard(settings: $model.recipe.tone, defaults: defaults.tone, reset: model.resetTone)
                LightShapingCard(
                    settings: $model.recipe.lightShaping,
                    defaults: defaults.lightShaping,
                    reset: model.resetLightShaping
                )
                LensBlurCard(settings: $model.recipe.lensBlur, defaults: defaults.lensBlur, reset: model.resetLensBlur)
                DiffusionCard(settings: $model.recipe.diffusion, defaults: defaults.diffusion, reset: model.resetDiffusion)
                HalationCard(settings: $model.recipe.halation, defaults: defaults.halation, reset: model.resetHalation)
                LandscapeGlowCard(
                    settings: $model.recipe.landscapeGlow,
                    defaults: defaults.landscapeGlow,
                    reset: model.resetLandscapeGlow
                )
                GrainCard(
                    settings: $model.recipe.grain,
                    defaults: defaults.grain,
                    reset: model.resetGrain,
                    randomize: model.randomizeGrain
                )
            }
            .padding(16)
        }
        .onChange(of: model.recipe) { _, _ in
            model.recipeDidChange()
        }
    }
}

private struct FilmToneCard: View {
    @Environment(AppModel.self) private var model
    @Binding var settings: FilmToneSettings
    let defaults: FilmToneSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Film Tone",
            symbol: "film",
            tint: .yellow,
            enabled: $settings.isEnabled,
            reset: reset,
            showsAdvanced: false
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Film Stock")
                    .font(.caption)
                FilmStockPickerButton(stock: Binding {
                    settings.stock
                } set: { stock in
                    model.changeAdjustments("Film Stock") {
                        settings.stock = stock
                        // Choosing a stock is a request to see it.
                        if stock != .none {
                            settings.isEnabled = true
                        }
                    }
                })
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ParameterSlider(
                "Stock Amount",
                value: $settings.stockAmount,
                default: defaults.stockAmount,
                range: 0 ... FilmToneSettings.maximumStockAmount,
                display: .strength
            )
                .disabled(settings.stock == .none)
                .opacity(settings.stock == .none ? 0.48 : 1)
            ParameterSlider(
                "Exposure",
                value: $settings.exposure,
                default: defaults.exposure,
                range: -2 ... 2,
                display: .exposure
            )
            ParameterSlider("Contrast", value: $settings.contrast, default: defaults.contrast, range: -1 ... 1)
            ParameterSlider("Saturation", value: $settings.saturation, default: defaults.saturation, range: -1 ... 1)
            ParameterSlider("Vibrance", value: $settings.vibrance, default: defaults.vibrance, range: -1 ... 1)
            ParameterSlider("Warmth", value: $settings.warmth, default: defaults.warmth, range: -1 ... 1)
        } advanced: {}
    }
}

private struct LightShapingCard: View {
    @Binding var settings: LightShapingSettings
    let defaults: LightShapingSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Vignette",
            symbol: "circle.dotted.circle",
            tint: .orange,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amountStops,
                default: defaults.amountStops,
                range: 0 ... LightShapingSettings.maximumAmount,
                undoName: "Vignette Amount"
            )
            ParameterSlider(
                "Focus",
                value: $settings.focus,
                default: defaults.focus,
                range: 0 ... 1,
                undoName: "Vignette Focus"
            )
        } advanced: {
            ParameterSlider("Pop", value: $settings.pop, default: defaults.pop, range: 0 ... 1)
            ParameterSlider("Bias", value: $settings.bias, default: defaults.bias, range: 0 ... 1)
            ParameterSlider("Roundness", value: $settings.roundness, default: defaults.roundness, range: 0 ... 1)
            CenterControlRow(
                title: "Center",
                target: .vignette,
                tint: .orange,
                x: $settings.centerX,
                y: $settings.centerY
            )
        }
    }
}

private struct LensBlurCard: View {
    @Binding var settings: LensBlurSettings
    let defaults: LensBlurSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Lens Blur",
            symbol: "drop.halffull",
            tint: .cyan,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amount,
                default: defaults.amount,
                range: 0 ... LensBlurSettings.maximumAmount,
                undoName: "Lens Blur Amount"
            )
            ParameterSlider("Falloff", value: $settings.falloff, default: defaults.falloff, range: 0 ... 1)
        } advanced: {
            ParameterSlider(
                "Chromatic Aberration",
                value: $settings.colorFringing,
                default: defaults.colorFringing,
                range: 0 ... 1
            )
            CenterControlRow(
                title: "Focus",
                target: .lensBlur,
                tint: .cyan,
                x: $settings.focusX,
                y: $settings.focusY
            )
        }
    }
}

private struct DiffusionCard: View {
    @Binding var settings: DiffusionSettings
    let defaults: DiffusionSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Diffusion",
            symbol: "circle.dotted",
            tint: .indigo,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amount,
                default: defaults.amount,
                range: 0 ... DiffusionSettings.maximumAmount,
                undoName: "Diffusion Amount"
            )
            ParameterSlider("Bloom", value: $settings.bloom, default: defaults.bloom, range: 0 ... 1)
        } advanced: {
            ParameterSlider("Veil", value: $settings.veil, default: defaults.veil, range: 0 ... 0.5)
            ParameterSlider("Source Bias", value: $settings.sourceBias, default: defaults.sourceBias, range: 0 ... 1)
            ParameterSlider(
                "Warmth",
                value: $settings.warmth,
                default: defaults.warmth,
                range: -1 ... 1,
                undoName: "Diffusion Warmth"
            )
        }
    }
}

private struct HalationCard: View {
    @Binding var settings: HalationSettings
    let defaults: HalationSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Halation",
            symbol: "sun.horizon",
            tint: .red,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amount,
                default: defaults.amount,
                range: 0 ... HalationSettings.maximumAmount,
                undoName: "Halation Amount"
            )
            ParameterSlider(
                "Spill Radius",
                value: $settings.spillRadius,
                default: defaults.spillRadius,
                range: 0 ... 1
            )
        } advanced: {
            ParameterSlider("Tail", value: $settings.tail, default: defaults.tail, range: 0 ... 1)
            ParameterSlider("Color Shift", value: $settings.colorShift, default: defaults.colorShift, range: 0 ... 1)
            ParameterSlider(
                "Saturation",
                value: $settings.saturation,
                default: defaults.saturation,
                range: 0 ... 1,
                undoName: "Halation Saturation"
            )
            ParameterSlider(
                "Green Leakage",
                value: $settings.greenLeakage,
                default: defaults.greenLeakage,
                range: 0 ... 0.5
            )
        }
    }
}

private struct LandscapeGlowCard: View {
    @Binding var settings: LandscapeGlowSettings
    let defaults: LandscapeGlowSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Landscape Glow",
            symbol: "mountain.2",
            symbolScale: 0.8,
            tint: .purple,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amount,
                default: defaults.amount,
                range: 0 ... LandscapeGlowSettings.maximumAmount,
                undoName: "Glow Amount"
            )
            ParameterSlider("Glow Size", value: $settings.glowSize, default: defaults.glowSize, range: 0 ... 1)
        } advanced: {
            ParameterSlider(
                "Shadow Protection",
                value: $settings.shadowProtection,
                default: defaults.shadowProtection,
                range: 0 ... 1
            )
            ParameterSlider("Detail", value: $settings.detail, default: defaults.detail, range: 0 ... 1)
        }
    }
}

private struct GrainCard: View {
    @Binding var settings: GrainSettings
    let defaults: GrainSettings
    let reset: () -> Void
    let randomize: () -> Void

    var body: some View {
        EffectCard(
            title: "Film Grain",
            symbol: "aqi.medium",
            symbolScale: 0.85,
            tint: .mint,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amount,
                default: defaults.amount,
                range: 0 ... GrainSettings.maximumAmount,
                undoName: "Grain Amount"
            )
            ParameterSlider(
                "Grain Size",
                value: $settings.grainSize,
                default: defaults.grainSize,
                range: 2 ... GrainSettings.maximumGrainSize,
                display: .grainSize
            )
        } advanced: {
            ParameterSlider("Acutance", value: $settings.acutance, default: defaults.acutance, range: 0 ... 1)
            ParameterSlider(
                "Size Variation",
                value: $settings.sizeVariation,
                default: defaults.sizeVariation,
                range: 0 ... 1
            )
            ParameterSlider("Chroma", value: $settings.chroma, default: defaults.chroma, range: 0 ... 1)
            ParameterSlider(
                "Shadow Response",
                value: $settings.shadowResponse,
                default: defaults.shadowResponse,
                range: 0 ... 1
            )
            ParameterSlider(
                "Highlight Response",
                value: $settings.highlightResponse,
                default: defaults.highlightResponse,
                range: 0 ... 1
            )
            Button("New Grain Pattern", systemImage: "dice", action: randomize)
                .buttonStyle(.borderless)
        }
    }
}

private struct EffectCard<Primary: View, Advanced: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let symbol: String
    /// Shrinks a symbol that's drawn wider or denser than the rest.
    var symbolScale: CGFloat = 1
    let tint: Color
    @Binding var enabled: Bool
    let reset: () -> Void
    var showsAdvanced = true
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let advanced: () -> Advanced

    @State private var isExpanded = false
    @State private var baseHeight: CGFloat = 0
    @State private var advancedHeight: CGFloat = 0
    @State private var baseMeasurementID = UUID()
    @State private var advancedMeasurementID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .scaleEffect(symbolScale)
                    .frame(width: 20)
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    model.changeAdjustments("Reset \(title)", reset)
                }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Reset \(title)")
                Toggle("Enable \(title)", isOn: animatedEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 9) {
                        primary()
                    }

                    if showsAdvanced {
                        Button {
                            withAnimation(moreAnimation) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                Text("More")
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .padding(.top, 12)
                        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                    }
                }
                .padding(.top, 12)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: AccordionHeightPreferenceKey.self,
                            value: [baseMeasurementID: proxy.size.height]
                        )
                    }
                }

                if showsAdvanced {
                    VStack(spacing: 9) {
                        advanced()
                    }
                    .padding(.top, 12)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: AccordionHeightPreferenceKey.self,
                                value: [advancedMeasurementID: proxy.size.height]
                            )
                        }
                    }
                    .allowsHitTesting(enabled && isExpanded)
                    .accessibilityHidden(!enabled || !isExpanded)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: visibleBodyHeight, alignment: .top)
            .mask {
                AccordionFeatherMask()
            }
            .allowsHitTesting(enabled)
            .accessibilityHidden(!enabled)
            .onPreferenceChange(AccordionHeightPreferenceKey.self) { measurements in
                if let measuredBaseHeight = measurements[baseMeasurementID],
                   abs(baseHeight - measuredBaseHeight) > 0.5 {
                    baseHeight = measuredBaseHeight
                }
                if let measuredAdvancedHeight = measurements[advancedMeasurementID],
                   abs(advancedHeight - measuredAdvancedHeight) > 0.5 {
                    advancedHeight = measuredAdvancedHeight
                }
            }
            .animation(effectAnimation, value: enabled)
            .animation(moreAnimation, value: isExpanded)
        }
        .padding(.horizontal, 13)
        .padding(.top, 13)
        .padding(.bottom, enabled ? 13 - featherClearance : 13)
        .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(effectAnimation, value: enabled)
    }

    private var animatedEnabled: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { newValue in
                withAnimation(effectAnimation) {
                    model.changeAdjustments(newValue ? "Enable \(title)" : "Disable \(title)") {
                        enabled = newValue
                    }
                }
            }
        )
    }

    private var effectAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .smooth(duration: 0.24)
    }

    private var moreAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .smooth(duration: 0.22)
    }

    private var visibleBodyHeight: CGFloat {
        guard enabled else { return 0 }
        // Let the feather finish in clear space after the last visible control.
        // The same amount is removed from the card's outer bottom inset, keeping
        // the final content-to-edge spacing unchanged.
        return baseHeight + (isExpanded ? advancedHeight : 0) + featherClearance
    }

    private var featherClearance: CGFloat { 10 }
}

private struct AccordionFeatherMask: View {
    var body: some View {
        GeometryReader { proxy in
            let featherHeight = min(10, proxy.size.height)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(.white)
                    .frame(height: max(0, proxy.size.height - featherHeight))
                LinearGradient(
                    colors: [.white, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: featherHeight)
            }
        }
    }
}

private struct AccordionHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// One adjustment: its name, its value and a slider. Double-click the name to
/// put back the recipe's own value, which a tick marks under the track; click
/// the value to type an exact one.
private struct ParameterSlider: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    @Binding var value: Double
    let defaultValue: Double
    let range: ClosedRange<Double>
    let display: ParameterDisplay
    /// What Edit ▸ Undo calls a change, where the title alone is ambiguous.
    let undoName: String

    /// The value being typed, while the readout is a field.
    @State private var typedValue: String?
    @FocusState private var isTyping: Bool
    @FocusState private var isSliderFocused: Bool

    init(
        _ title: String,
        value: Binding<Double>,
        default defaultValue: Double,
        range: ClosedRange<Double>,
        display: ParameterDisplay? = nil,
        undoName: String? = nil
    ) {
        self.title = title
        _value = value
        self.defaultValue = defaultValue
        self.range = range
        self.display = display ?? .proportion(in: range)
        self.undoName = undoName ?? title
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                // The double-click lives on the label alone, so a single click
                // on the readout isn't held back waiting for a second one.
                HStack {
                    Text(title)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: resetToDefault)
                .help("Double-click to reset to the recipe’s value")
                readout
            }
            .font(.caption)

            Slider(value: sliderValue, in: range) { isEditing in
                // Letting go ends the drag's undo step.
                if !isEditing {
                    model.endCoalescedChanges(undoKey)
                }
            }
            .tint(.accentColor)
            .background(SliderDoubleClickReset(perform: resetToDefault))
            .background {
                DefaultValueTick(fraction: defaultFraction)
            }
            .focused($isSliderFocused)
            .onChange(of: isSliderFocused) { _, isFocused in
                if !isFocused {
                    model.endCoalescedChanges(undoKey)
                }
            }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                let direction: Double = press.key == .leftArrow || press.key == .downArrow ? -1 : 1
                nudge(by: direction * (press.modifiers.contains(.shift) ? 10 : 1))
                return .handled
            }
            .accessibilityLabel(title)
            .accessibilityValue(display.accessibilityText(for: value))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: nudge(by: 1)
                case .decrement: nudge(by: -1)
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Reset to Recipe Value", resetToDefault)
        }
    }

    @ViewBuilder private var readout: some View {
        if typedValue != nil {
            HStack(spacing: 3) {
                TextField(title, text: typedText)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 40)
                    .padding(.horizontal, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .focused($isTyping)
                    .task { isTyping = true }
                    .background(EndEditingOnOutsideClick())
                    .onSubmit(commitTypedValue)
                    .onExitCommand { typedValue = nil }
                    .onChange(of: isTyping) { _, isTyping in
                        // Moving on keeps what was typed, as in any Mac field.
                        if !isTyping {
                            commitTypedValue()
                        }
                    }
                    .accessibilityLabel(title)
                if !display.unit.symbol.isEmpty {
                    Text(display.unit.symbol)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Button {
                typedValue = display.editingText(for: value)
            } label: {
                Text(display.text(for: value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.horizontalText)
            .help("Click to type a value")
            .accessibilityLabel("\(title) Value")
            .accessibilityValue(display.accessibilityText(for: value))
            .accessibilityHint("Type an exact value")
        }
    }

    private var sliderValue: Binding<Double> {
        Binding {
            value
        } set: { newValue in
            setValue(newValue, as: undoName, coalescing: true)
        }
    }

    private var typedText: Binding<String> {
        Binding {
            typedValue ?? ""
        } set: { text in
            typedValue = text
        }
    }

    /// Where the recipe's own value sits along the track.
    private var defaultFraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (defaultValue - range.lowerBound) / span))
    }

    /// One slider's drags and nudges each make a single undo step.
    private var undoKey: String {
        "slider \(undoName)"
    }

    private func setValue(_ newValue: Double, as actionName: String, coalescing: Bool = false) {
        model.changeAdjustments(actionName, coalescingKey: coalescing ? undoKey : nil) {
            value = newValue
        }
    }

    private func resetToDefault() {
        guard isEnabled else { return }
        setValue(defaultValue, as: "Reset \(undoName)")
    }

    private func nudge(by steps: Double) {
        setValue(display.stepped(value, by: steps, in: range), as: undoName, coalescing: true)
    }

    private func commitTypedValue() {
        guard let text = typedValue else { return }
        typedValue = nil
        guard let typed = display.storedValue(from: text, in: range) else {
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                NSSound.beep()
            }
            return
        }
        setValue(typed, as: undoName)
    }
}

/// Double-clicking a slider resets it, as in other Mac creative apps. The
/// slider is an AppKit control that keeps its clicks to itself, so this
/// watches for double-clicks landing on it rather than adding a gesture.
private struct SliderDoubleClickReset: NSViewRepresentable {
    let perform: () -> Void

    func makeNSView(context: Context) -> WatchingView {
        let view = WatchingView()
        view.perform = perform
        return view
    }

    func updateNSView(_ view: WatchingView, context: Context) {
        view.perform = perform
    }

    final class WatchingView: NSView {
        var perform: () -> Void = {}
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.clickCount == 2, event.window === self.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point) {
                    // After the slider has taken the click, so the reset wins.
                    DispatchQueue.main.async { self.perform() }
                }
                return event
            }
        }
    }
}

/// Ends typing in a field when the next click lands anywhere else, which
/// AppKit doesn't do by itself for clicks on non-focusable content.
struct EndEditingOnOutsideClick: NSViewRepresentable {
    func makeNSView(context: Context) -> WatchingView { WatchingView() }
    func updateNSView(_ view: WatchingView, context: Context) {}

    final class WatchingView: NSView {
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if !self.bounds.contains(point) {
                    // Giving up first responder commits the field.
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }
    }
}

/// A small mark under the track at the recipe's own value, covered by the
/// knob when the slider sits there.
private struct DefaultValueTick: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            // The knob's centre travels between half its width from either end.
            let inset: CGFloat = 10
            Capsule()
                .fill(.secondary)
                .frame(width: 2, height: 3)
                .position(
                    x: inset + (proxy.size.width - inset * 2) * fraction,
                    y: proxy.size.height / 2 + 6
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CenterControlRow: View {
    @Environment(AppModel.self) private var model

    let title: String
    let target: EffectCenterTarget
    let tint: Color
    @Binding var x: Double
    @Binding var y: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer()

            HStack(spacing: 7) {
                Text("X \(percentage(x))")
                Text("Y \(percentage(y))")
            }
            .monospacedDigit()
            .foregroundStyle(.secondary)

            Button {
                withAnimation(.smooth(duration: 0.18)) {
                    model.showOriginal = false
                    model.activeCenterTarget = isActive ? nil : target
                }
            } label: {
                Image(systemName: isActive ? "scope" : "viewfinder")
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isActive ? tint : nil)
            .disabled(model.selectedSourceURL == nil)
            .help(isActive ? "Finish adjusting \(title.lowercased())" : "Adjust \(title.lowercased()) on image")
            .accessibilityLabel(isActive ? "Finish \(target.title) center adjustment" : "Adjust \(target.title) center on image")
        }
        .font(.caption)
    }

    private var isActive: Bool {
        model.activeCenterTarget == target
    }

    private func percentage(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}
