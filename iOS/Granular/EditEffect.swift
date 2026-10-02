import GranularCore

/// The seven effects on the dial row, in the order of the Mac's inspector,
/// each with the adjustments the phone offers for it.
enum EditEffect: String, CaseIterable, Identifiable {
    case tone
    case vignette
    case lensBlur
    case diffusion
    case halation
    case glow
    case grain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tone: "Film Tone"
        case .vignette: "Vignette"
        case .lensBlur: "Lens Blur"
        case .diffusion: "Diffusion"
        case .halation: "Halation"
        case .glow: "Landscape Glow"
        case .grain: "Film Grain"
        }
    }

    /// The name under the dial, short enough for seven across.
    var shortTitle: String {
        switch self {
        case .tone: "Tone"
        case .vignette: "Vignette"
        case .lensBlur: "Blur"
        case .diffusion: "Diffusion"
        case .halation: "Halation"
        case .glow: "Glow"
        case .grain: "Grain"
        }
    }

    var symbol: String {
        switch self {
        case .tone: "film"
        case .vignette: "camera.aperture"
        case .lensBlur: "drop.halffull"
        case .diffusion: "circle.dotted"
        case .halation: "sun.horizon"
        case .glow: "sun.max.fill"
        case .grain: "aqi.medium"
        }
    }

    var isEnabled: WritableKeyPath<FilmRecipe, Bool> {
        switch self {
        case .tone: \.tone.isEnabled
        case .vignette: \.lightShaping.isEnabled
        case .lensBlur: \.lensBlur.isEnabled
        case .diffusion: \.diffusion.isEnabled
        case .halation: \.halation.isEnabled
        case .glow: \.landscapeGlow.isEnabled
        case .grain: \.grain.isEnabled
        }
    }

    /// Film Tone leads with its stock, chosen from a strip of thumbnails
    /// rather than dialled in.
    var hasStock: Bool { self == .tone }

    var parameters: [EffectParameter] {
        switch self {
        case .tone:
            [
                EffectParameter("Amount", \.tone.stockAmount, 0 ... FilmToneSettings.maximumStockAmount, display: .strength),
                EffectParameter("Exposure", \.tone.exposure, -2 ... 2, display: .exposure),
                EffectParameter("Contrast", \.tone.contrast, -1 ... 1),
                EffectParameter("Saturation", \.tone.saturation, -1 ... 1),
                EffectParameter("Vibrance", \.tone.vibrance, -1 ... 1),
                EffectParameter("Warmth", \.tone.warmth, -1 ... 1)
            ]
        case .vignette:
            [
                EffectParameter("Amount", \.lightShaping.amountStops, 0 ... LightShapingSettings.maximumAmount),
                EffectParameter("Focus", \.lightShaping.focus, 0 ... 1)
            ]
        case .lensBlur:
            [
                EffectParameter("Amount", \.lensBlur.amount, 0 ... LensBlurSettings.maximumAmount),
                EffectParameter("Falloff", \.lensBlur.falloff, 0 ... 1)
            ]
        case .diffusion:
            [
                EffectParameter("Amount", \.diffusion.amount, 0 ... DiffusionSettings.maximumAmount),
                EffectParameter("Bloom", \.diffusion.bloom, 0 ... 1)
            ]
        case .halation:
            [
                EffectParameter("Amount", \.halation.amount, 0 ... HalationSettings.maximumAmount),
                EffectParameter("Spill Radius", \.halation.spillRadius, 0 ... 1)
            ]
        case .glow:
            [
                EffectParameter("Amount", \.landscapeGlow.amount, 0 ... LandscapeGlowSettings.maximumAmount),
                EffectParameter("Glow Size", \.landscapeGlow.glowSize, 0 ... 1)
            ]
        case .grain:
            [
                EffectParameter("Amount", \.grain.amount, 0 ... GrainSettings.maximumAmount),
                EffectParameter("Grain Size", \.grain.grainSize, 2 ... GrainSettings.maximumGrainSize, display: .grainSize)
            ]
        }
    }

    /// How much of the effect is dialled in, from 0 to 1, for the dial's ring.
    func strength(in recipe: FilmRecipe) -> Double {
        if self == .tone, recipe.tone.stock == .none {
            return recipe.tone.hasToneAdjustments ? 0.5 : 0
        }
        guard let amount = parameters.first else { return 0 }
        let value = recipe[keyPath: amount.value]
        return min(1, max(0, (value - amount.range.lowerBound) / (amount.range.upperBound - amount.range.lowerBound)))
    }

    /// Puts the effect back as the recipe has it.
    func reset(_ recipe: inout FilmRecipe, to original: FilmRecipe) {
        switch self {
        case .tone: recipe.tone = original.tone
        case .vignette: recipe.lightShaping = original.lightShaping
        case .lensBlur: recipe.lensBlur = original.lensBlur
        case .diffusion: recipe.diffusion = original.diffusion
        case .halation: recipe.halation = original.halation
        case .glow: recipe.landscapeGlow = original.landscapeGlow
        case .grain: recipe.grain = original.grain
        }
    }

    func isModified(_ recipe: FilmRecipe, from original: FilmRecipe) -> Bool {
        var reset = recipe
        self.reset(&reset, to: original)
        return reset != recipe
    }
}

struct EffectParameter: Identifiable {
    let title: String
    let value: WritableKeyPath<FilmRecipe, Double>
    let range: ClosedRange<Double>
    let display: ParameterDisplay

    var id: String { title }

    init(_ title: String, _ value: WritableKeyPath<FilmRecipe, Double>, _ range: ClosedRange<Double>, display: ParameterDisplay? = nil) {
        self.title = title
        self.value = value
        self.range = range
        self.display = display ?? .proportion(in: range)
    }
}
