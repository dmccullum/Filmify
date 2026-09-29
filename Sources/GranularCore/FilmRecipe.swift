import Foundation

public enum FilmStockFamily: String, CaseIterable, Sendable {
    case colorNegative
    case cinema
    case slide
    case instant
    case blackAndWhite

    public var title: String {
        switch self {
        case .colorNegative: "Color Negative"
        case .cinema: "Cinema"
        case .slide: "Slide"
        case .instant: "Instant"
        case .blackAndWhite: "Black & White"
        }
    }

    public var stocks: [FilmStockID] {
        FilmStockID.allCases.filter { $0.family == self }
    }
}

public enum FilmStockID: String, CaseIterable, Codable, Hashable, Sendable {
    case none
    case portra400
    case ektar100
    case gold200
    case pro400H
    case superia400
    case vision250D
    case vision500T
    case eterna500
    case optima100
    case velvia100F
    case eliteChrome
    case e100G
    case e200
    case kodachrome64
    case instax
    case fp100C
    case triX400
    case hp5

    /// Stocks from earlier versions that were folded into a close neighbor.
    static let retiredAliases: [String: FilmStockID] = [
        "portra160": .portra400,
        "superiaReala": .superia400,
        "velvia50": .velvia100F,
        "ektachrome100D": .e100G,
        "ultramax400": .gold200,
        "c200": .superia400,
        "provia100F": .e100G,
        "doubleX": .hp5
    ]

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        // A recipe from another version must never fail to load over one stock.
        self = FilmStockID(rawValue: rawValue) ?? Self.retiredAliases[rawValue] ?? .none
    }

    public var name: String {
        switch self {
        case .none: "None"
        case .portra400: "Portra 400"
        case .ektar100: "Ektar 100"
        case .gold200: "Gold 200"
        case .pro400H: "Pro 400H"
        case .superia400: "Superia 400"
        case .vision250D: "Vision3 250D"
        case .vision500T: "Vision3 500T"
        case .eterna500: "Eterna 500"
        case .optima100: "Optima 100"
        case .velvia100F: "Velvia 100F"
        case .eliteChrome: "Elite Chrome"
        case .e100G: "E100G"
        case .e200: "E200"
        case .kodachrome64: "Kodachrome 64"
        case .instax: "Instax"
        case .fp100C: "FP-100C"
        case .triX400: "Tri-X 400"
        case .hp5: "HP5 Plus"
        }
    }

    /// A one-line description of the stock's character.
    public var vibe: String {
        switch self {
        case .none: "The image's own color"
        case .portra400: "Soft contrast, warm and forgiving skin"
        case .ektar100: "Vivid, saturated and punchy"
        case .gold200: "Golden, nostalgic warmth"
        case .pro400H: "Airy pastels and minty greens"
        case .superia400: "Cool greens, classic drugstore Fuji"
        case .vision250D: "Clean, natural daylight cinema"
        case .vision500T: "Cool tungsten night"
        case .eterna500: "Quiet, desaturated cinema"
        case .optima100: "Crisp European color with cool, quiet greens"
        case .velvia100F: "Dense, electric landscape color"
        case .eliteChrome: "Punchy slide with deep, inky shadows"
        case .e100G: "Fine, true-to-life slide with clear blues"
        case .e200: "Soft slide with gentle, muted greens"
        case .kodachrome64: "Rich reds, deep shadows"
        case .instax: "Bright, soft and faded"
        case .fp100C: "Pale peel-apart instant with lifted blacks"
        case .triX400: "Gritty, contrasty black and white"
        case .hp5: "Open, gentle black and white"
        }
    }

    public var family: FilmStockFamily? {
        switch self {
        case .none: nil
        case .portra400, .ektar100, .gold200, .pro400H, .superia400, .optima100:
            .colorNegative
        case .vision250D, .vision500T, .eterna500: .cinema
        case .velvia100F, .eliteChrome, .e100G, .e200, .kodachrome64: .slide
        case .instax, .fp100C: .instant
        case .triX400, .hp5: .blackAndWhite
        }
    }

    public var isMonochrome: Bool {
        family == .blackAndWhite
    }

    /// The share of the cube's own density curve that reaches the image. Film
    /// Tone's Contrast and Exposure stay in charge of tone, so soft negatives
    /// keep little of theirs while slide and black-and-white film keep more.
    var toneRetention: Double {
        switch self {
        case .vision250D, .eterna500: 0.25
        case .vision500T: 0.30
        // Fitted characters carry their own tone curve in full.
        default: 1
        }
    }

    /// The spectral cube for stocks without a fitted character.
    var resourceName: String? {
        switch self {
        case .vision250D: "vision3_250d"
        case .vision500T: "vision3_500t"
        case .eterna500: "eterna_500"
        default: nil
        }
    }

}

public struct FilmToneSettings: Codable, Hashable, Sendable {
    public static let maximumStockAmount = 2.0

    public var isEnabled: Bool
    public var stock: FilmStockID
    public var stockAmount: Double
    public var exposure: Double
    public var contrast: Double
    public var saturation: Double
    public var vibrance: Double
    public var warmth: Double

    public init(
        isEnabled: Bool = true,
        stock: FilmStockID = .none,
        stockAmount: Double = 1,
        exposure: Double = 0,
        contrast: Double = 0,
        saturation: Double = 0,
        vibrance: Double = 0,
        warmth: Double = 0
    ) {
        self.isEnabled = isEnabled
        self.stock = stock
        self.stockAmount = stockAmount
        self.exposure = exposure
        self.contrast = contrast
        self.saturation = saturation
        self.vibrance = vibrance
        self.warmth = warmth
    }

    public var isNeutral: Bool {
        (stock == .none || stockAmount == 0)
            && !hasToneAdjustments
    }

    public var hasToneAdjustments: Bool {
        exposure != 0
            || contrast != 0
            || saturation != 0
            || vibrance != 0
            || warmth != 0
    }

}

public struct LightShapingSettings: Codable, Hashable, Sendable {
    public static let maximumAmount = 1.0

    public var isEnabled: Bool
    public var amountStops: Double
    public var focus: Double
    public var pop: Double
    public var bias: Double
    public var roundness: Double
    public var centerX: Double
    public var centerY: Double

    public init(
        isEnabled: Bool = true,
        amountStops: Double = 0.25,
        focus: Double = 0.55,
        pop: Double = 0.5,
        bias: Double = 0.5,
        roundness: Double = 0.5,
        centerX: Double = 0.5,
        centerY: Double = 0.5
    ) {
        self.isEnabled = isEnabled
        self.amountStops = amountStops
        self.focus = focus
        self.pop = pop
        self.bias = bias
        self.roundness = roundness
        self.centerX = centerX
        self.centerY = centerY
    }
}

public struct LensBlurSettings: Codable, Hashable, Sendable {
    public static let maximumAmount = 1.0

    public var isEnabled: Bool
    public var amount: Double
    public var falloff: Double
    public var colorFringing: Double
    public var focusX: Double
    public var focusY: Double

    public init(
        isEnabled: Bool = false,
        amount: Double = 0.25,
        falloff: Double = 0.55,
        colorFringing: Double = 0.075,
        focusX: Double = 0.5,
        focusY: Double = 0.5
    ) {
        self.isEnabled = isEnabled
        self.amount = amount
        self.falloff = falloff
        self.colorFringing = colorFringing
        self.focusX = focusX
        self.focusY = focusY
    }

}

public struct DiffusionSettings: Codable, Hashable, Sendable {
    public static let maximumAmount = 1.0

    public var isEnabled: Bool
    public var amount: Double
    public var bloom: Double
    public var veil: Double
    public var sourceBias: Double
    public var warmth: Double

    public init(
        isEnabled: Bool = true,
        amount: Double = 0.25,
        bloom: Double = 0.35,
        veil: Double = 0.1,
        sourceBias: Double = 0.25,
        warmth: Double = 0
    ) {
        self.isEnabled = isEnabled
        self.amount = amount
        self.bloom = bloom
        self.veil = veil
        self.sourceBias = sourceBias
        self.warmth = warmth
    }
}

public struct HalationSettings: Codable, Hashable, Sendable {
    public static let maximumAmount = 1.0

    public var isEnabled: Bool
    public var amount: Double
    public var spillRadius: Double
    public var tail: Double
    public var colorShift: Double
    public var saturation: Double
    public var greenLeakage: Double

    public init(
        isEnabled: Bool = true,
        amount: Double = 0.25,
        spillRadius: Double = 0.35,
        tail: Double = 0.35,
        colorShift: Double = 0.5,
        saturation: Double = 0.65,
        greenLeakage: Double = 0.12
    ) {
        self.isEnabled = isEnabled
        self.amount = amount
        self.spillRadius = spillRadius
        self.tail = tail
        self.colorShift = colorShift
        self.saturation = saturation
        self.greenLeakage = greenLeakage
    }
}

public struct LandscapeGlowSettings: Codable, Hashable, Sendable {
    public static let maximumAmount = 1.0

    public var isEnabled: Bool
    public var amount: Double
    public var glowSize: Double
    public var shadowProtection: Double
    public var detail: Double

    public init(
        isEnabled: Bool = false,
        amount: Double = 0.25,
        glowSize: Double = 0.5,
        shadowProtection: Double = 0.72,
        detail: Double = 0.7
    ) {
        self.isEnabled = isEnabled
        self.amount = amount
        self.glowSize = glowSize
        self.shadowProtection = shadowProtection
        self.detail = detail
    }
}

public struct GrainSettings: Codable, Hashable, Sendable {
    public static let maximumAmount = 1.0
    public static let maximumGrainSize = 60.0

    public var isEnabled: Bool
    public var amount: Double
    public var grainSize: Double
    public var acutance: Double
    public var sizeVariation: Double
    public var chroma: Double
    public var shadowResponse: Double
    public var highlightResponse: Double
    public var seed: UInt32

    public init(
        isEnabled: Bool = true,
        amount: Double = 0.25,
        grainSize: Double = 9,
        acutance: Double = 0.55,
        sizeVariation: Double = 0.25,
        chroma: Double = 0.12,
        shadowResponse: Double = 0.72,
        highlightResponse: Double = 0.28,
        seed: UInt32 = 2_016
    ) {
        self.isEnabled = isEnabled
        self.amount = amount
        self.grainSize = grainSize
        self.acutance = acutance
        self.sizeVariation = sizeVariation
        self.chroma = chroma
        self.shadowResponse = shadowResponse
        self.highlightResponse = highlightResponse
        self.seed = seed
    }
}

public struct FilmRecipe: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var tone: FilmToneSettings
    public var lightShaping: LightShapingSettings
    public var lensBlur: LensBlurSettings
    public var diffusion: DiffusionSettings
    public var halation: HalationSettings
    public var landscapeGlow: LandscapeGlowSettings
    public var grain: GrainSettings

    public init(
        id: String,
        name: String,
        tone: FilmToneSettings = .init(),
        lightShaping: LightShapingSettings,
        lensBlur: LensBlurSettings = .init(),
        diffusion: DiffusionSettings,
        halation: HalationSettings,
        landscapeGlow: LandscapeGlowSettings = .init(),
        grain: GrainSettings
    ) {
        self.id = id
        self.name = name
        self.tone = tone
        self.lightShaping = lightShaping
        self.lensBlur = lensBlur
        self.diffusion = diffusion
        self.halation = halation
        self.landscapeGlow = landscapeGlow
        self.grain = grain
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case tone
        case lightShaping
        case lensBlur
        case diffusion
        case halation
        case landscapeGlow
        case grain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tone = try container.decodeIfPresent(FilmToneSettings.self, forKey: .tone) ?? .init()
        lightShaping = try container.decode(LightShapingSettings.self, forKey: .lightShaping)
        lensBlur = try container.decodeIfPresent(LensBlurSettings.self, forKey: .lensBlur) ?? .init()
        diffusion = try container.decode(DiffusionSettings.self, forKey: .diffusion)
        halation = try container.decode(HalationSettings.self, forKey: .halation)
        landscapeGlow = try container.decodeIfPresent(
            LandscapeGlowSettings.self,
            forKey: .landscapeGlow
        ) ?? .init()
        grain = try container.decode(GrainSettings.self, forKey: .grain)
    }

}

public extension FilmRecipe {
    static let builtIns: [FilmRecipe] = [
        FilmRecipe(
            id: "clean-120",
            name: "Clean 120",
            tone: .init(isEnabled: false),
            lightShaping: .init(amountStops: 0.10, focus: 0.68),
            diffusion: .init(amount: 0.10, bloom: 0.2, veil: 0.03),
            halation: .init(amount: 0.10, spillRadius: 0.20, tail: 0.2),
            grain: .init(amount: 0.15, grainSize: 3.86, chroma: 0.05)
        ),
        FilmRecipe(
            id: "classic-35",
            name: "Classic 35",
            tone: .init(isEnabled: false),
            lightShaping: .init(amountStops: 0.25, focus: 0.56),
            diffusion: .init(amount: 0.06, bloom: 0.35, veil: 0.10),
            halation: .init(amount: 0.15, spillRadius: 0.35, tail: 0.35),
            grain: .init(amount: 0.17, grainSize: 10, chroma: 0.12)
        ),
        FilmRecipe(
            id: "extra-35",
            name: "Extra 35",
            tone: .init(isEnabled: false),
            lightShaping: .init(amountStops: 0.25, focus: 0.56),
            diffusion: .init(amount: 0.10, bloom: 0.35, veil: 0.10),
            halation: .init(amount: 0.25, spillRadius: 0.35, tail: 0.35),
            grain: .init(amount: 0.25, grainSize: 10, chroma: 0.12)
        ),
        FilmRecipe(
            id: "soft-16",
            name: "Soft 16",
            tone: .init(isEnabled: false),
            lightShaping: .init(amountStops: 0.50, focus: 0.48),
            diffusion: .init(amount: 0.40, bloom: 0.50, veil: 0.16),
            halation: .init(amount: 0.40, spillRadius: 0.5, tail: 0.52),
            grain: .init(
                amount: 0.25,
                grainSize: 30,
                acutance: 0.42,
                sizeVariation: 0.50,
                chroma: 0.98,
                shadowResponse: 0.72,
                highlightResponse: 0.28
            )
        )
    ]

    static var classic35: FilmRecipe {
        builtIns.first { $0.id == "classic-35" }!
    }

}
