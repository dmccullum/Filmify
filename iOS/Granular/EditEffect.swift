import GranularCore

/// The tools under the photo, in the order of the Mac's inspector. Film
/// Tone is split three ways, so no tool needs more than three sliders.
enum EditEffect: String, CaseIterable, Identifiable {
    case film
    case light
    case color
    case vignette
    case lensBlur
    case diffusion
    case halation
    case glow
    case grain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .film: "Film"
        case .light: "Light"
        case .color: "Color"
        case .vignette: "Vignette"
        case .lensBlur: "Lens Blur"
        case .diffusion: "Diffusion"
        case .halation: "Halation"
        case .glow: "Landscape Glow"
        case .grain: "Film Grain"
        }
    }

    var symbol: String {
        switch self {
        case .film: "film"
        case .light: "circle.lefthalf.filled"
        case .color: "paintpalette"
        case .vignette: "circle.rectangle.filled.pattern.diagonalline"
        case .lensBlur: "drop.halffull"
        case .diffusion: "circle.dotted"
        case .halation: "sun.horizon"
        case .glow: "sun.max.fill"
        case .grain: "aqi.medium"
        }
    }

    /// Film, Light and Color are all Film Tone, so they're on or off together.
    /// On iPhone they're never turned off: Film has None, and Light and
    /// Color are adjustments rather than effects.
    var isEnabled: WritableKeyPath<FilmRecipe, Bool> {
        switch self {
        case .film, .light, .color: \.tone.isEnabled
        case .vignette: \.lightShaping.isEnabled
        case .lensBlur: \.lensBlur.isEnabled
        case .diffusion: \.diffusion.isEnabled
        case .halation: \.halation.isEnabled
        case .glow: \.landscapeGlow.isEnabled
        case .grain: \.grain.isEnabled
        }
    }

    /// Whether the tool can be turned off, rather than only set to nothing.
    var isToggleable: Bool {
        switch self {
        case .film, .light, .color: false
        default: true
        }
    }

    /// Film leads with its stock, chosen from a strip of thumbnails rather
    /// than dialled in.
    var hasStock: Bool { self == .film }

    var parameters: [EffectParameter] {
        switch self {
        case .film:
            [EffectParameter("Amount", \.tone.stockAmount, 0 ... FilmToneSettings.maximumStockAmount, display: .strength)]
        case .light:
            [
                EffectParameter("Exposure", \.tone.exposure, -2 ... 2, display: .exposure),
                EffectParameter("Contrast", \.tone.contrast, -1 ... 1)
            ]
        case .color:
            [
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

    /// The most sliders any tool has, which sets the panel's height.
    static let mostParameters = allCases.map(\.parameters.count).max() ?? 0

    /// Puts the tool's part of the look back as the recipe has it.
    func reset(_ recipe: inout FilmRecipe, to original: FilmRecipe) {
        switch self {
        case .film:
            recipe.tone.isEnabled = original.tone.isEnabled
            recipe.tone.stock = original.tone.stock
            recipe.tone.stockAmount = original.tone.stockAmount
        case .light, .color:
            for parameter in parameters {
                recipe[keyPath: parameter.value] = original[keyPath: parameter.value]
            }
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
        // Film Tone coming on by itself, as an edit turns it on, isn't a change.
        if !isToggleable { reset.tone.isEnabled = recipe.tone.isEnabled }
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
