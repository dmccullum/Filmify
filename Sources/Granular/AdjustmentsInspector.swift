import GranularCore
import SwiftUI

struct AdjustmentsInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

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

                FilmToneCard(settings: $model.recipe.tone, reset: model.resetTone)
                LightShapingCard(settings: $model.recipe.lightShaping, reset: model.resetLightShaping)
                LensBlurCard(settings: $model.recipe.lensBlur, reset: model.resetLensBlur)
                DiffusionCard(settings: $model.recipe.diffusion, reset: model.resetDiffusion)
                HalationCard(settings: $model.recipe.halation, reset: model.resetHalation)
                LandscapeGlowCard(settings: $model.recipe.landscapeGlow, reset: model.resetLandscapeGlow)
                GrainCard(
                    settings: $model.recipe.grain,
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
    @Binding var settings: FilmToneSettings
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
                    settings.stock = stock
                    // Choosing a stock is a request to see it.
                    if stock != .none {
                        settings.isEnabled = true
                    }
                })
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ParameterSlider(
                "Stock Amount",
                value: $settings.stockAmount,
                range: 0 ... FilmToneSettings.maximumStockAmount
            )
                .disabled(settings.stock == .none)
                .opacity(settings.stock == .none ? 0.48 : 1)
            ParameterSlider("Exposure", value: $settings.exposure, range: -2 ... 2, suffix: "EV", decimals: 1)
            ParameterSlider("Contrast", value: $settings.contrast, range: -1 ... 1)
            ParameterSlider("Saturation", value: $settings.saturation, range: -1 ... 1)
            ParameterSlider("Vibrance", value: $settings.vibrance, range: -1 ... 1)
            ParameterSlider("Warmth", value: $settings.warmth, range: -1 ... 1)
        } advanced: {}
    }
}

private struct LightShapingCard: View {
    @Binding var settings: LightShapingSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Vignette",
            symbol: "camera.aperture",
            tint: .orange,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider("Amount", value: $settings.amountStops, range: 0 ... LightShapingSettings.maximumAmount)
            ParameterSlider("Focus", value: $settings.focus, range: 0 ... 1)
        } advanced: {
            ParameterSlider("Pop", value: $settings.pop, range: 0 ... 1)
            ParameterSlider("Bias", value: $settings.bias, range: 0 ... 1)
            ParameterSlider("Roundness", value: $settings.roundness, range: 0 ... 1)
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
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Lens Blur",
            symbol: "drop.halffull",
            tint: .cyan,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider("Amount", value: $settings.amount, range: 0 ... LensBlurSettings.maximumAmount)
            ParameterSlider("Falloff", value: $settings.falloff, range: 0 ... 1)
        } advanced: {
            ParameterSlider("Chromatic Aberration", value: $settings.colorFringing, range: 0 ... 1)
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
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Diffusion",
            symbol: "circle.dotted",
            tint: .indigo,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider("Amount", value: $settings.amount, range: 0 ... DiffusionSettings.maximumAmount)
            ParameterSlider("Bloom", value: $settings.bloom, range: 0 ... 1)
        } advanced: {
            ParameterSlider("Veil", value: $settings.veil, range: 0 ... 0.5)
            ParameterSlider("Source Bias", value: $settings.sourceBias, range: 0 ... 1)
            ParameterSlider("Warmth", value: $settings.warmth, range: -1 ... 1)
        }
    }
}

private struct HalationCard: View {
    @Binding var settings: HalationSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Halation",
            symbol: "sun.horizon",
            tint: .red,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider("Amount", value: $settings.amount, range: 0 ... HalationSettings.maximumAmount)
            ParameterSlider("Spill Radius", value: $settings.spillRadius, range: 0 ... 1)
        } advanced: {
            ParameterSlider("Tail", value: $settings.tail, range: 0 ... 1)
            ParameterSlider("Color Shift", value: $settings.colorShift, range: 0 ... 1)
            ParameterSlider("Saturation", value: $settings.saturation, range: 0 ... 1)
            ParameterSlider("Green Leakage", value: $settings.greenLeakage, range: 0 ... 0.5)
        }
    }
}

private struct LandscapeGlowCard: View {
    @Binding var settings: LandscapeGlowSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Landscape Glow",
            symbol: "sun.max.fill",
            tint: .purple,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amount,
                range: 0 ... LandscapeGlowSettings.maximumAmount
            )
            ParameterSlider("Glow Size", value: $settings.glowSize, range: 0 ... 1)
        } advanced: {
            ParameterSlider("Shadow Protection", value: $settings.shadowProtection, range: 0 ... 1)
            ParameterSlider("Detail", value: $settings.detail, range: 0 ... 1)
        }
    }
}

private struct GrainCard: View {
    @Binding var settings: GrainSettings
    let reset: () -> Void
    let randomize: () -> Void

    var body: some View {
        EffectCard(
            title: "Film Grain",
            symbol: "aqi.medium",
            tint: .mint,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider("Amount", value: $settings.amount, range: 0 ... GrainSettings.maximumAmount)
            ParameterSlider("Grain Size", value: $settings.grainSize, range: 2 ... GrainSettings.maximumGrainSize, decimals: 1)
        } advanced: {
            ParameterSlider("Acutance", value: $settings.acutance, range: 0 ... 1)
            ParameterSlider("Size Variation", value: $settings.sizeVariation, range: 0 ... 1)
            ParameterSlider("Chroma", value: $settings.chroma, range: 0 ... 1)
            ParameterSlider("Shadow Response", value: $settings.shadowResponse, range: 0 ... 1)
            ParameterSlider("Highlight Response", value: $settings.highlightResponse, range: 0 ... 1)
            Button("New Grain Pattern", systemImage: "dice", action: randomize)
                .buttonStyle(.borderless)
        }
    }
}

private struct EffectCard<Primary: View, Advanced: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let symbol: String
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
                    .frame(width: 20)
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
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
                    enabled = newValue
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

private struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var suffix = ""
    var decimals = 2

    init(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String = "",
        decimals: Int = 2
    ) {
        self.title = title
        _value = value
        self.range = range
        self.suffix = suffix
        self.decimals = decimals
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedValue)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(value: $value, in: range)
                .tint(.accentColor)
        }
    }

    private var formattedValue: String {
        let number = value.formatted(.number.precision(.fractionLength(decimals)))
        return suffix.isEmpty ? number : "\(number) \(suffix)"
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
