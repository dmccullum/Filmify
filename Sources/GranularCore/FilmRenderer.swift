import CoreGraphics
import CoreImage
import Foundation

public enum FilmRendererError: LocalizedError {
    case kernelCompilationFailed(String)
    case filmStockUnavailable(String)
    case filmStockMalformed(String)
    case imageLoadFailed(URL)
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .kernelCompilationFailed(let name):
            "Granular could not compile its \(name) image kernel."
        case .filmStockUnavailable(let name):
            "Granular could not load the \(name) color stock."
        case .filmStockMalformed(let name):
            "The bundled \(name) color stock is not a valid 3D LUT."
        case .imageLoadFailed(let url):
            "Granular could not open \(url.lastPathComponent)."
        case .renderFailed:
            "Granular could not render the image."
        }
    }
}

public final class FilmRenderer: @unchecked Sendable {
    private let toneKernel: CIColorKernel
    private let stockInputKernel: CIColorKernel
    private let stockOutputKernel: CIColorKernel
    private let characterKernel: CIColorKernel
    private let lightShapingKernel: CIColorKernel
    private let lensRadialBlurKernel: CIKernel
    private let lensChromaticKernel: CIKernel
    private let diffusionKernel: CIColorKernel
    private let halationKernel: CIColorKernel
    private let landscapeGlowExtractionKernel: CIColorKernel
    private let landscapeGlowKernel: CIColorKernel
    private let grainKernel: CIColorKernel
    private let stockCubeLock = NSLock()
    private var stockCubes: [FilmStockID: FilmStockCube] = [:]

    public init() throws {
        guard let toneKernel = CIColorKernel(source: Self.toneSource) else {
            throw FilmRendererError.kernelCompilationFailed("film-tone")
        }
        guard let stockInputKernel = CIColorKernel(source: Self.stockInputSource) else {
            throw FilmRendererError.kernelCompilationFailed("color-stock input")
        }
        guard let stockOutputKernel = CIColorKernel(source: Self.stockOutputSource) else {
            throw FilmRendererError.kernelCompilationFailed("color-stock output")
        }
        guard let characterKernel = CIColorKernel(source: Self.characterSource) else {
            throw FilmRendererError.kernelCompilationFailed("film-character")
        }
        guard let lightShapingKernel = CIColorKernel(source: Self.lightShapingSource) else {
            throw FilmRendererError.kernelCompilationFailed("light-shaping")
        }
        guard let lensRadialBlurKernel = CIKernel(source: Self.lensRadialBlurSource) else {
            throw FilmRendererError.kernelCompilationFailed("lens-blur")
        }
        guard let lensChromaticKernel = CIKernel(source: Self.lensChromaticSource) else {
            throw FilmRendererError.kernelCompilationFailed("chromatic-aberration")
        }
        guard let diffusionKernel = CIColorKernel(source: Self.diffusionSource) else {
            throw FilmRendererError.kernelCompilationFailed("diffusion")
        }
        guard let halationKernel = CIColorKernel(source: Self.halationSource) else {
            throw FilmRendererError.kernelCompilationFailed("halation")
        }
        guard let landscapeGlowExtractionKernel = CIColorKernel(
            source: Self.landscapeGlowExtractionSource
        ) else {
            throw FilmRendererError.kernelCompilationFailed("landscape-glow source")
        }
        guard let landscapeGlowKernel = CIColorKernel(source: Self.landscapeGlowSource) else {
            throw FilmRendererError.kernelCompilationFailed("landscape-glow")
        }
        guard let grainKernel = CIColorKernel(source: Self.grainSource) else {
            throw FilmRendererError.kernelCompilationFailed("grain")
        }

        self.toneKernel = toneKernel
        self.stockInputKernel = stockInputKernel
        self.stockOutputKernel = stockOutputKernel
        self.characterKernel = characterKernel
        self.lightShapingKernel = lightShapingKernel
        self.lensRadialBlurKernel = lensRadialBlurKernel
        self.lensChromaticKernel = lensChromaticKernel
        self.diffusionKernel = diffusionKernel
        self.halationKernel = halationKernel
        self.landscapeGlowExtractionKernel = landscapeGlowExtractionKernel
        self.landscapeGlowKernel = landscapeGlowKernel
        self.grainKernel = grainKernel
    }

    public func loadImage(at url: URL) throws -> CIImage {
        let options: [CIImageOption: Any] = [
            .applyOrientationProperty: true
        ]
        guard let image = CIImage(contentsOf: url, options: options) else {
            throw FilmRendererError.imageLoadFailed(url)
        }
        return image
    }

    public func render(
        _ source: CIImage,
        recipe: FilmRecipe,
        previewMaximumDimension: CGFloat? = nil,
        grainDimension: CGFloat? = nil
    ) throws -> CIImage {
        var extent = source.extent.integral
        guard !extent.isEmpty else { throw FilmRendererError.renderFailed }

        var image = try renderFilmTone(source, tone: recipe.tone)

        if recipe.lightShaping.isEnabled, recipe.lightShaping.amountStops != 0 {
            image = try applyLightShaping(image, settings: recipe.lightShaping, extent: extent)
        }
        if recipe.lensBlur.isEnabled, recipe.lensBlur.amount != 0 {
            image = try applyLensBlur(image, settings: recipe.lensBlur, extent: extent)
        }
        if recipe.diffusion.isEnabled, recipe.diffusion.amount != 0 {
            image = try applyDiffusion(image, settings: recipe.diffusion, extent: extent)
        }
        if recipe.halation.isEnabled, recipe.halation.amount != 0 {
            image = try applyHalation(image, settings: recipe.halation, extent: extent)
        }
        if recipe.landscapeGlow.isEnabled, recipe.landscapeGlow.amount != 0 {
            image = try applyLandscapeGlow(image, settings: recipe.landscapeGlow, extent: extent)
        }
        // Resolve optical effects at source resolution, then generate grain on
        // the final preview grid so downsampling does not dilute its contrast.
        if let maximumDimension = previewMaximumDimension, maximumDimension > 0 {
            let scale = min(1, maximumDimension / max(extent.width, extent.height))
            if scale < 1 {
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                extent = image.extent.integral
            }
        }
        if recipe.grain.isEnabled, recipe.grain.amount != 0 {
            // A quick preview resolves everything else small, but grain is
            // generated on the grid it will be shown at; stretching it up from
            // the small grid would make it blocky.
            if let grainDimension, grainDimension > 0 {
                let scale = grainDimension / max(extent.width, extent.height)
                if scale > 1 {
                    image = image.samplingLinear()
                        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    extent = image.extent.integral
                }
            }
            image = try applyGrain(image, settings: recipe.grain, extent: extent)
        }

        return image.cropped(to: extent)
    }

    /// Applies only the Film Tone stage: tone adjustments, then the color stock.
    public func renderFilmTone(_ source: CIImage, tone: FilmToneSettings) throws -> CIImage {
        let extent = source.extent.integral
        guard tone.isEnabled, !extent.isEmpty else { return source }

        var image = source
        if tone.hasToneAdjustments {
            image = try applyTone(image, settings: tone, extent: extent)
        }
        if tone.stock != .none, tone.stockAmount > 0 {
            image = try applyFilmStock(image, settings: tone, extent: extent)
        }
        return image
    }

    private func applyTone(
        _ image: CIImage,
        settings: FilmToneSettings,
        extent: CGRect
    ) throws -> CIImage {
        let arguments: [Any] = [
            image,
            Float(max(-2, min(2, settings.exposure))),
            Float(max(-1, min(1, settings.contrast))),
            Float(max(-1, min(1, settings.saturation))),
            Float(max(-1, min(1, settings.vibrance))),
            Float(max(-1, min(1, settings.warmth)))
        ]
        guard let output = toneKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    private func applyFilmStock(
        _ image: CIImage,
        settings: FilmToneSettings,
        extent: CGRect
    ) throws -> CIImage {
        let character = settings.stock.character
        // Cubes carry their own shoulder, so ease highlights in before the
        // lookup. A fitted character already describes its roll-off.
        let knee: Float = character == nil ? 0.82 : 1
        guard let input = stockInputKernel.apply(extent: extent, arguments: [image, knee]) else {
            throw FilmRendererError.renderFailed
        }

        let graded: CIImage
        if let character {
            guard let output = characterKernel.apply(
                extent: extent,
                arguments: [input] + Self.characterArguments(character)
            ) else {
                throw FilmRendererError.renderFailed
            }
            graded = output
        } else {
            let cube = try stockCube(for: settings.stock)
            guard let filter = CIFilter(name: "CIColorCube") else {
                throw FilmRendererError.renderFailed
            }
            filter.setValue(input, forKey: kCIInputImageKey)
            filter.setValue(cube.dimension, forKey: "inputCubeDimension")
            filter.setValue(cube.data, forKey: "inputCubeData")
            guard let output = filter.outputImage?.cropped(to: extent) else {
                throw FilmRendererError.renderFailed
            }
            graded = output
        }

        let amount = Float(max(0, min(FilmToneSettings.maximumStockAmount, settings.stockAmount)))
        let colorAmount = settings.stock.isMonochrome ? min(amount, 1) : amount
        guard let output = stockOutputKernel.apply(
            extent: extent,
            arguments: [
                image,
                graded,
                Float(character == nil ? settings.stock.toneRetention : 1),
                colorAmount,
                amount
            ]
        ) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    static func characterArguments(_ character: FilmCharacter) -> [Any] {
        let curves = (0 ..< FilmCharacter.curveKnots.count).map { index in
            CIVector(
                x: FilmCharacter.curveKnots[index] + character.red[index],
                y: FilmCharacter.curveKnots[index] + character.green[index],
                z: FilmCharacter.curveKnots[index] + character.blue[index]
            )
        }
        let sectors = (0 ..< FilmCharacter.hueCenters.count).map { index in
            CIVector(
                x: character.lightness[index],
                y: character.chroma[index],
                z: character.hue[index]
            )
        }
        let saturation = CIVector(
            x: character.highlightDesaturation,
            y: character.shadowSaturation
        )
        return curves + sectors + [saturation]
    }

    private func stockCube(for stock: FilmStockID) throws -> FilmStockCube {
        stockCubeLock.lock()
        if let cached = stockCubes[stock] {
            stockCubeLock.unlock()
            return cached
        }
        stockCubeLock.unlock()

        let loaded = try FilmStockLUTLoader.load(stock)
        stockCubeLock.lock()
        stockCubes[stock] = loaded
        stockCubeLock.unlock()
        return loaded
    }

    private func applyLightShaping(
        _ image: CIImage,
        settings: LightShapingSettings,
        extent: CGRect
    ) throws -> CIImage {
        let arguments: [Any] = [
            image,
            CIVector(cgRect: extent),
            Float(Self.mappedSpotlightAmount(settings.amountStops)),
            Float(settings.focus),
            Float(settings.pop),
            Float(settings.bias),
            Float(settings.roundness),
            CIVector(x: settings.centerX, y: settings.centerY)
        ]
        guard let output = lightShapingKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    private func applyLensBlur(
        _ image: CIImage,
        settings: LensBlurSettings,
        extent: CGRect
    ) throws -> CIImage {
        let amount = Self.mappedLensBlurAmount(settings.amount)
        let rgbSeparation = Self.mappedLensBlurRGBSeparation(settings.colorFringing)
        let shortEdge = min(extent.width, extent.height)
        // Kromo's polar-space Gaussian reaches roughly one percent of image width
        // plus height at strength 1. Granular keeps that calibration, but performs
        // the convolution directly on the GPU around the user-selected center.
        let maximumBlurOffset = (extent.width + extent.height) * 0.01 * amount
        let maximumChromaticOffset = shortEdge * 0.044 * rgbSeparation
        let roiExpansion = ceil(maximumBlurOffset + maximumChromaticOffset + 3)
        let clamped = image.clampedToExtent()
        let center = CIVector(x: settings.focusX, y: settings.focusY)
        let blurArguments: [Any] = [
            clamped,
            CIVector(cgRect: extent),
            Float(maximumBlurOffset),
            Float(settings.falloff),
            center
        ]
        guard let radialBlur = lensRadialBlurKernel.apply(
            extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -roiExpansion, dy: -roiExpansion) },
            arguments: blurArguments
        ) else {
            throw FilmRendererError.renderFailed
        }

        let chromaticArguments: [Any] = [
            radialBlur,
            CIVector(cgRect: extent),
            Float(settings.falloff),
            Float(rgbSeparation),
            center
        ]
        guard let output = lensChromaticKernel.apply(
            extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -maximumChromaticOffset - 2, dy: -maximumChromaticOffset - 2) },
            arguments: chromaticArguments
        ) else {
            throw FilmRendererError.renderFailed
        }
        return output.cropped(to: extent)
    }

    private func applyDiffusion(
        _ image: CIImage,
        settings: DiffusionSettings,
        extent: CGRect
    ) throws -> CIImage {
        var output = image
        for passAmount in Self.opticalPassAmounts(for: Self.mappedOpticalAmount(settings.amount)) {
            output = try applyDiffusionPass(
                output,
                settings: settings,
                amount: passAmount,
                extent: extent
            )
        }
        return output
    }

    private func applyDiffusionPass(
        _ image: CIImage,
        settings: DiffusionSettings,
        amount: Double,
        extent: CGRect
    ) throws -> CIImage {
        let shortEdge = min(extent.width, extent.height)
        let detailRadius = max(0.8, shortEdge * (0.00045 + 0.0018 * settings.bloom))
        let bloomRadius = max(3.0, shortEdge * (0.0030 + 0.0120 * settings.bloom))
        let wideRadius = bloomRadius * (2.5 + 1.5 * settings.bloom)
        let detail = gaussianBlur(image, radius: detailRadius, extent: extent)
        let bloom = gaussianBlur(image, radius: bloomRadius, extent: extent)
        let wide = gaussianBlur(image, radius: wideRadius, extent: extent)

        let arguments: [Any] = [
            image,
            detail,
            bloom,
            wide,
            Float(amount),
            Float(settings.bloom),
            Float(settings.veil),
            Float(settings.sourceBias),
            Float(settings.warmth)
        ]
        guard let output = diffusionKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    private func applyHalation(
        _ image: CIImage,
        settings: HalationSettings,
        extent: CGRect
    ) throws -> CIImage {
        var output = image
        for passAmount in Self.opticalPassAmounts(for: Self.mappedOpticalAmount(settings.amount)) {
            output = try applyHalationPass(
                output,
                settings: settings,
                amount: passAmount,
                extent: extent
            )
        }
        return output
    }

    private func applyHalationPass(
        _ image: CIImage,
        settings: HalationSettings,
        amount: Double,
        extent: CGRect
    ) throws -> CIImage {
        let shortEdge = min(extent.width, extent.height)
        let baseRadius = max(0.75, shortEdge * (0.00045 + 0.0022 * settings.spillRadius))
        let middleRadius = baseRadius * (2.0 + settings.tail)
        let farRadius = baseRadius * (4.0 + settings.tail * 5.0)

        let near = gaussianBlur(image, radius: baseRadius, extent: extent)
        let middle = gaussianBlur(image, radius: middleRadius, extent: extent)
        let far = gaussianBlur(image, radius: farRadius, extent: extent)

        let arguments: [Any] = [
            image,
            near,
            middle,
            far,
            Float(amount),
            Float(settings.tail),
            Float(settings.colorShift),
            Float(settings.saturation),
            Float(settings.greenLeakage)
        ]
        guard let output = halationKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    private func applyLandscapeGlow(
        _ image: CIImage,
        settings: LandscapeGlowSettings,
        extent: CGRect
    ) throws -> CIImage {
        let shortEdge = min(extent.width, extent.height)
        let size = max(0, min(1, settings.glowSize))

        // All scales follow the image dimensions so the frequency separation and
        // highlight tail remain consistent across preview and export sizes.
        let middleRadius = max(4, shortEdge * (0.0045 + 0.0135 * size))
        let wideRadius = middleRadius * (2.25 + 1.75 * size)
        let overall = gaussianBlur(image, radius: middleRadius * 0.72, extent: extent)
        guard let highlightSource = landscapeGlowExtractionKernel.apply(
            extent: extent,
            arguments: [image]
        ) else {
            throw FilmRendererError.renderFailed
        }
        let middle = gaussianBlur(highlightSource, radius: middleRadius, extent: extent)
        let wide = gaussianBlur(highlightSource, radius: wideRadius, extent: extent)

        let arguments: [Any] = [
            image,
            overall,
            middle,
            wide,
            Float(max(0, min(LandscapeGlowSettings.maximumAmount, settings.amount))),
            Float(max(0, min(1, settings.shadowProtection))),
            Float(max(0, min(1, settings.detail)))
        ]
        guard let output = landscapeGlowKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    static func opticalPassAmounts(for amount: Double) -> [Double] {
        let clampedAmount = max(0, min(2, amount))
        guard clampedAmount > 0 else { return [] }
        if clampedAmount <= 1 {
            return [clampedAmount]
        }
        return [1, clampedAmount - 1]
    }

    static func mappedOpticalAmount(_ amount: Double) -> Double {
        min(1, max(0, amount)) * 2
    }

    static func mappedSpotlightAmount(_ amount: Double) -> Double {
        min(1, max(0, amount)) * 4
    }

    static func mappedLensBlurAmount(_ amount: Double) -> Double {
        min(1, max(0, amount)) * 4
    }

    static func mappedLensBlurRGBSeparation(_ amount: Double) -> Double {
        min(1, max(0, amount)) * 2
    }

    private func applyGrain(
        _ image: CIImage,
        settings: GrainSettings,
        extent: CGRect
    ) throws -> CIImage {
        // Treat the long edge as the 36 mm film dimension in either orientation.
        let particlePixels = max(
            0.20,
            min(10, max(extent.width, extent.height) * settings.grainSize / 36_000)
        )
        // Film granularity follows the density of a small surrounding area, not the
        // brightness of each finished pixel in isolation. A softly resolved guide
        // keeps fine edges and specular detail from visibly switching grain regimes.
        let shortEdge = min(extent.width, extent.height)
        let densityGuideRadius = max(2, min(16, max(particlePixels * 2.25, shortEdge * 0.0015)))
        let densityGuide = gaussianBlur(image, radius: densityGuideRadius, extent: extent)

        let arguments: [Any] = [
            image,
            densityGuide,
            CIVector(cgRect: extent),
            Float(Self.mappedGrainAmount(settings.amount)),
            Float(particlePixels),
            Float(settings.acutance),
            Float(settings.sizeVariation),
            Float(settings.chroma),
            Float(settings.shadowResponse),
            Float(settings.highlightResponse),
            Self.mappedGrainSeed(settings.seed)
        ]
        guard let output = grainKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    static func mappedGrainAmount(_ amount: Double) -> Double {
        min(1, max(0, amount)) * 4.224
    }

    static func mappedGrainSeed(_ seed: UInt32) -> Float {
        // Core Image Kernel Language receives scalar arguments as 32-bit floats.
        // Keeping the phase bounded prevents large UInt32 values from collapsing
        // nearby hash inputs into the same representable number on the GPU.
        Float(seed % 1_000_003)
    }

    private func gaussianBlur(_ image: CIImage, radius: CGFloat, extent: CGRect) -> CIImage {
        image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
    }

}

private extension FilmRenderer {
    static let stockInputSource = #"""
    float srgbEncode(float value) {
        float linear = max(value, 0.0);
        return linear <= 0.0031308
            ? linear * 12.92
            : 1.055 * pow(linear, 1.0 / 2.4) - 0.055;
    }

    kernel vec4 prepareFilmStock(__sample pixel, float knee) {
        vec3 rec2020 = max(pixel.rgb, vec3(0.0));
        vec3 rgb = vec3(
            1.6604910 * rec2020.r - 0.5876411 * rec2020.g - 0.0728499 * rec2020.b,
            -0.1245505 * rec2020.r + 1.1328999 * rec2020.g - 0.0083494 * rec2020.b,
            -0.0181508 * rec2020.r - 0.1005789 * rec2020.g + 1.1187297 * rec2020.b
        );

        // The spectral cubes describe display-referred sRGB. Compress wide-gamut
        // excursions toward neutral before lookup instead of clipping individual
        // channels, which would create hard, synthetic hue changes.
        float y = max(dot(rgb, vec3(0.2126, 0.7152, 0.0722)), 0.0);
        if (y > knee) {
            float width = max(1.0 - knee, 0.02);
            float rolledY = knee + width * (1.0 - exp(-(y - knee) / width));
            rgb *= rolledY / max(y, 0.000001);
            y = rolledY;
        }
        float minimum = min(rgb.r, min(rgb.g, rgb.b));
        float maximum = max(rgb.r, max(rgb.g, rgb.b));
        float lowScale = minimum < 0.0 ? y / max(y - minimum, 0.000001) : 1.0;
        float highScale = maximum > 1.0
            ? (1.0 - y) / max(maximum - y, 0.000001)
            : 1.0;
        rgb = mix(vec3(y), rgb, clamp(min(lowScale, highScale), 0.0, 1.0));

        return vec4(
            srgbEncode(rgb.r),
            srgbEncode(rgb.g),
            srgbEncode(rgb.b),
            pixel.a
        );
    }
    """#

    static let characterSource = #"""
    float srgbToLinear(float value) {
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4);
    }

    float linearToSrgb(float value) {
        float linear = max(value, 0.0);
        return linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1.0 / 2.4) - 0.055;
    }

    float sectorWeight(float hue, float center) {
        float difference = mod(hue - center + 3.14159265, 6.28318531) - 3.14159265;
        return max(1.0 - abs(difference) / 1.04719755, 0.0);
    }

    float curve(float value, float k0, float k1, float k2, float k3, float k4, float k5) {
        float x = clamp(value, 0.0, 1.0);
        if (x < 0.125) { return mix(k0, k1, x / 0.125); }
        if (x < 0.25) { return mix(k1, k2, (x - 0.125) / 0.125); }
        if (x < 0.5) { return mix(k2, k3, (x - 0.25) / 0.25); }
        if (x < 0.75) { return mix(k3, k4, (x - 0.5) / 0.25); }
        return mix(k4, k5, (x - 0.75) / 0.25);
    }

    kernel vec4 filmCharacter(
        __sample pixel,
        vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4, vec3 c5,
        vec3 red, vec3 yellow, vec3 green, vec3 cyan, vec3 blue, vec3 magenta,
        vec2 saturation
    ) {
        vec3 rgb = clamp(pixel.rgb, 0.0, 1.0);
        vec3 linear = vec3(srgbToLinear(rgb.r), srgbToLinear(rgb.g), srgbToLinear(rgb.b));
        vec3 lms = vec3(
            0.4122214708 * linear.r + 0.5363325363 * linear.g + 0.0514459929 * linear.b,
            0.2119034982 * linear.r + 0.6806995451 * linear.g + 0.1073969566 * linear.b,
            0.0883024619 * linear.r + 0.2817188376 * linear.g + 0.6299787005 * linear.b
        );
        lms = pow(max(lms, vec3(0.0)), vec3(0.33333333));
        float lightness = 0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z;
        float a = 1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z;
        float b = 0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z;

        float chroma = length(vec2(a, b));
        float hue = atan(b, a);
        // Hue edits fade out toward neutral so grays keep only the curves' tint.
        float colorWeight = clamp(chroma / 0.08, 0.0, 1.0);
        float w0 = sectorWeight(hue, 0.52359878);
        float w1 = sectorWeight(hue, 1.57079633);
        float w2 = sectorWeight(hue, 2.61799388);
        float w3 = sectorWeight(hue, 3.66519143);
        float w4 = sectorWeight(hue, 4.71238898);
        float w5 = sectorWeight(hue, 5.75958653);
        vec3 edit = (w0 * red + w1 * yellow + w2 * green + w3 * cyan + w4 * blue + w5 * magenta)
            * colorWeight;

        lightness += edit.x;
        chroma *= exp(edit.y);
        chroma *= (1.0 - saturation.x * clamp((lightness - 0.6) / 0.4, 0.0, 1.0))
            * (1.0 + saturation.y * clamp((0.6 - lightness) / 0.6, 0.0, 1.0));
        hue += edit.z;
        a = chroma * cos(hue);
        b = chroma * sin(hue);

        vec3 root = vec3(
            lightness + 0.3963377774 * a + 0.2158037573 * b,
            lightness - 0.1055613458 * a - 0.0638541728 * b,
            lightness - 0.0894841775 * a - 1.2914855480 * b
        );
        lms = root * root * root;
        linear = vec3(
            4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
            -1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
            -0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z
        );
        rgb = clamp(
            vec3(linearToSrgb(linear.r), linearToSrgb(linear.g), linearToSrgb(linear.b)),
            0.0,
            1.0
        );

        return vec4(
            curve(rgb.r, c0.x, c1.x, c2.x, c3.x, c4.x, c5.x),
            curve(rgb.g, c0.y, c1.y, c2.y, c3.y, c4.y, c5.y),
            curve(rgb.b, c0.z, c1.z, c2.z, c3.z, c4.z, c5.z),
            pixel.a
        );
    }
    """#

    static let stockOutputSource = #"""
    float srgbDecode(float value) {
        float encoded = max(value, 0.0);
        return encoded <= 0.04045
            ? encoded / 12.92
            : pow((encoded + 0.055) / 1.055, 2.4);
    }

    kernel vec4 finishFilmStock(
        __sample source,
        __sample graded,
        float toneRetention,
        float colorAmount,
        float toneAmount
    ) {
        vec3 srgb = vec3(
            srgbDecode(graded.r),
            srgbDecode(graded.g),
            srgbDecode(graded.b)
        );
        vec3 rec2020 = vec3(
            0.6274039 * srgb.r + 0.3292830 * srgb.g + 0.0433131 * srgb.b,
            0.0690973 * srgb.r + 0.9195404 * srgb.g + 0.0113623 * srgb.b,
            0.0163914 * srgb.r + 0.0880133 * srgb.g + 0.8955953 * srgb.b
        );
        const vec3 luma = vec3(0.2627002, 0.6779981, 0.0593017);
        vec3 positiveGrade = max(rec2020, vec3(0.0));
        float sourceY = max(dot(source.rgb, luma), 0.0);
        float gradedY = max(dot(positiveGrade, luma), 0.000001);

        // These spectral cubes include a complete film density response, but Film
        // Tone's own controls stay in charge of tone. Each stock keeps its own
        // share of the cube's luminance move, so slide film reads denser than a
        // soft negative, while its chromatic signature is kept whole.
        float restrainedY = mix(sourceY, gradedY, toneRetention);
        vec3 colorGrade = positiveGrade * (restrainedY / gradedY);
        vec3 rgb = mix(source.rgb, colorGrade, colorAmount);

        // Color and tone share one amount except for black-and-white stocks,
        // whose color cannot be extrapolated past gray without inverting hues.
        float mixedY = dot(rgb, luma);
        float targetY = max(mix(sourceY, restrainedY, toneAmount), 0.0);
        if (abs(mixedY) > 0.000001) {
            rgb *= targetY / mixedY;
        }
        return vec4(rgb, source.a);
    }
    """#

    static let toneSource = #"""
    float filmShoulder(float value) {
        float a = 0.15;
        float b = 0.50;
        float c = 0.10;
        float d = 0.20;
        float e = 0.02;
        float f = 0.30;
        return ((value * (a * value + c * b) + d * e)
            / (value * (a * value + b) + d * f)) - e / f;
    }

    float outputShoulder(float value, float knee) {
        float width = max(1.0 - knee, 0.0001);
        float over = max(value - knee, 0.0);
        float rolled = knee + width * (1.0 - exp(-over / width));
        return value > knee ? rolled : value;
    }

    vec3 rec2020ToOklab(vec3 rgb) {
        float x = 0.6369580 * rgb.r + 0.1446169 * rgb.g + 0.1688809 * rgb.b;
        float y = 0.2627002 * rgb.r + 0.6779981 * rgb.g + 0.0593017 * rgb.b;
        float z =                         0.0280727 * rgb.g + 1.0609851 * rgb.b;

        float l = 0.8190224 * x + 0.3619063 * y - 0.1288738 * z;
        float m = 0.0329837 * x + 0.9292868 * y + 0.0361447 * z;
        float s = 0.0481772 * x + 0.2642395 * y + 0.6335478 * z;
        float lRoot = pow(max(l, 0.0), 0.3333333);
        float mRoot = pow(max(m, 0.0), 0.3333333);
        float sRoot = pow(max(s, 0.0), 0.3333333);

        return vec3(
            0.2104543 * lRoot + 0.7936178 * mRoot - 0.0040720 * sRoot,
            1.9780000 * lRoot - 2.4285922 * mRoot + 0.4505937 * sRoot,
            0.0259040 * lRoot + 0.7827718 * mRoot - 0.8086758 * sRoot
        );
    }

    vec3 oklabToRec2020(vec3 lab) {
        float lRoot = lab.x + 0.3963378 * lab.y + 0.2158038 * lab.z;
        float mRoot = lab.x - 0.1055613 * lab.y - 0.0638542 * lab.z;
        float sRoot = lab.x - 0.0894842 * lab.y - 1.2914855 * lab.z;
        float l = lRoot * lRoot * lRoot;
        float m = mRoot * mRoot * mRoot;
        float s = sRoot * sRoot * sRoot;

        float x = 1.2268799 * l - 0.5578150 * m + 0.2813911 * s;
        float y = -0.0405757 * l + 1.1122868 * m - 0.0717111 * s;
        float z = -0.0763729 * l - 0.4214933 * m + 1.5869240 * s;

        return vec3(
            1.7166512 * x - 0.3556708 * y - 0.2533663 * z,
            -0.6666844 * x + 1.6164812 * y + 0.0157685 * z,
            0.0176399 * x - 0.0427706 * y + 0.9421031 * z
        );
    }

    kernel vec4 filmTone(__sample pixel, float exposure, float contrast, float saturation, float vibrance, float warmth) {
        const vec3 luma = vec3(0.2627002, 0.6779981, 0.0593017);
        vec3 source = max(pixel.rgb, vec3(0.0));
        float sourceY = max(dot(source, luma), 0.000001);

        // Exposure uses a bounded photographic density curve. The family composes
        // cleanly around fixed black and white points: +1 EV gives deep tones about
        // three times their input density, then progressively reduces that gain
        // through the mids and highlights. This matches the response of modern raw
        // editors much more closely than multiplying RGB and applying a late knee.
        float densityGain = pow(3.05, exposure);
        float exposedY = sourceY * densityGain
            / max(1.0 + (densityGain - 1.0) * sourceY, 0.000001);
        float adjustedStops = log2(max(exposedY, 0.000001) / 0.18);

        // Contrast is an S-curve around 18% gray. A bounded soft-sign curve limits
        // toward both endpoints instead of driving highlights and shadows into clips.
        float contrastPosition = adjustedStops * 0.62;
        float contrastCurve = contrastPosition / (1.0 + abs(contrastPosition));
        adjustedStops += contrast * 1.15 * contrastCurve;
        float adjustedY = 0.18 * exp2(adjustedStops);

        // Contrast adds a normalized film response without making exposure itself
        // collide with a second shoulder.
        float filmY = filmShoulder(adjustedY)
            * (0.18 / max(filmShoulder(0.18), 0.000001));
        float rolloff = clamp(abs(contrast) * 0.23, 0.0, 0.36);
        adjustedY = mix(adjustedY, filmY, rolloff);

        // Retain a hair of printable separation below display white at positive
        // exposure instead of letting the last highlight values quantize together.
        adjustedY -= 0.0035
            * clamp(max(exposure, 0.0), 0.0, 1.0)
            * smoothstep(0.85, 1.0, adjustedY);

        // SDR source values remain below white by construction. Compress only
        // genuinely extended input rather than flattening ordinary upper mids.
        adjustedY = adjustedY > 1.0
            ? 0.995
            : adjustedY;
        vec3 rgb = source * (adjustedY / sourceY);

        // Saturation and Vibrance live in OKLab so equal slider moves feel much more
        // even across hues. Vibrance favors restrained colors, protects skin-like
        // orange hues, and eases off in the brightest part of the image.
        vec3 lab = rec2020ToOklab(max(rgb, vec3(0.0)));
        float chroma = length(lab.yz);

        // Raising exposure on photographic material does not preserve electronic
        // RGB saturation all the way to white. Compress dye separation gradually
        // through the raised mids, then more firmly in the shoulder. At +1 EV this
        // is calibrated against a Lightroom reference; the user's Saturation and
        // Vibrance controls remain available afterward for intentional color moves.
        float exposureColorWeight = clamp(max(exposure, 0.0), 0.0, 1.0);
        float raisedMidCompression = smoothstep(0.10, 0.75, adjustedY);
        float shoulderCompression = smoothstep(0.75, 0.98, adjustedY);
        float exposureChromaScale = 1.0 - exposureColorWeight
            * (0.45 * raisedMidCompression + 0.18 * shoulderCompression);
        lab.yz *= max(0.30, exposureChromaScale);

        float saturationScale = saturation >= 0.0
            ? 1.0 + saturation * 1.35
            : 1.0 + saturation;
        lab.yz *= saturationScale;

        float directionLength = max(length(lab.yz), 0.000001);
        vec2 hueDirection = lab.yz / directionLength;
        float skinDirection = clamp(dot(hueDirection, normalize(vec2(0.78, 0.62))), 0.0, 1.0);
        float skinProtection = smoothstep(0.70, 0.94, skinDirection)
            * smoothstep(0.008, 0.055, chroma)
            * (1.0 - smoothstep(0.25, 0.38, chroma));
        float chromaProtection = smoothstep(0.035, 0.28, chroma);
        float highlightProtection = 1.0 - 0.35 * smoothstep(0.72, 1.08, lab.x);
        float vibranceScale = vibrance >= 0.0
            ? 1.0 + vibrance * 1.25 * (1.0 - chromaProtection)
                * (1.0 - 0.92 * skinProtection) * highlightProtection
            : exp2(vibrance * 1.05);
        lab.yz *= max(0.0, vibranceScale);

        // Warmth leans toward a Kodak Gold-like palette: yellow-gold density through
        // the mids and highlights, with cleaner, less-red shadow color separation.
        float highlightTone = smoothstep(0.42, 0.96, lab.x);
        float shadowTone = 1.0 - smoothstep(0.08, 0.46, lab.x);
        float midtoneTone = smoothstep(0.16, 0.52, lab.x)
            * (1.0 - smoothstep(0.68, 1.02, lab.x));
        lab.y += warmth * (0.007 + 0.006 * midtoneTone
            + 0.004 * highlightTone - 0.006 * shadowTone);
        lab.z += warmth * (0.027 + 0.021 * midtoneTone
            + 0.022 * highlightTone - 0.014 * shadowTone);

        // A small density response keeps newly saturated colors rich rather than
        // electronic, then pulls out-of-gamut negative channels toward neutral.
        float colorIncrease = max(0.0, saturationScale * vibranceScale - 1.0);
        lab.x -= min(0.012, colorIncrease * min(chroma, 0.25) * 0.05);
        rgb = oklabToRec2020(lab);
        float y = max(dot(rgb, luma), 0.000001);
        float minimum = min(rgb.r, min(rgb.g, rgb.b));
        float gamutScale = minimum < 0.0 ? y / max(y - minimum, 0.000001) : 1.0;
        rgb = max(vec3(0.0), mix(vec3(y), rgb, clamp(gamutScale, 0.0, 1.0)));

        // As luminance enters the shoulder, compress only the chroma that no longer
        // fits below display white. This gives film-like highlight desaturation and
        // prevents one channel from clipping early and producing a colored edge.
        float maximum = max(rgb.r, max(rgb.g, rgb.b));
        float colorExcursion = max(maximum - y, 0.0);
        float availableExcursion = max(1.0 - y, 0.0);
        float highlightGamutScale = colorExcursion > availableExcursion
            ? availableExcursion / max(colorExcursion, 0.000001)
            : 1.0;
        rgb = mix(vec3(y), rgb, clamp(highlightGamutScale, 0.0, 1.0));
        if (sourceY > 1.0) {
            rgb = min(rgb, vec3(0.99));
        }

        return vec4(rgb, pixel.a);
    }
    """#

    static let lightShapingSource = #"""
    kernel vec4 lightShape(__sample pixel, vec4 extent, float amount, float focus, float pop, float bias, float roundness, vec2 center) {
        vec2 uv = (destCoord() - extent.xy) / extent.zw;
        vec2 delta = uv - center;
        float aspect = extent.z / max(extent.w, 1.0);
        delta.x *= mix(1.0, aspect, clamp(roundness, 0.0, 1.0));
        float corner = length(vec2(0.5 * mix(1.0, aspect, clamp(roundness, 0.0, 1.0)), 0.5));
        float distanceFromCenter = length(delta) / max(corner, 0.001);
        float inner = mix(0.08, 0.82, clamp(focus, 0.0, 1.0));
        float falloff = smoothstep(inner, 1.0, distanceFromCenter);
        float centerLift = (bias - 0.5) * amount * 0.35 * (1.0 - falloff);
        float edgeLoss = amount * falloff * mix(1.15, 0.8, bias);
        float gain = exp2(centerLift - edgeLoss);
        vec3 rgb = pixel.rgb * gain;
        float contrast = 1.0 + (pop - 0.5) * amount * 0.16;
        rgb = max(vec3(0.0), (rgb - vec3(0.18)) * contrast + vec3(0.18));
        return vec4(rgb, pixel.a);
    }
    """#

    static let lensRadialBlurSource = #"""
    kernel vec4 lensRadialBlur(
        sampler source,
        vec4 extent,
        float maximumOffset,
        float falloff,
        vec2 center
    ) {
        vec2 coordinate = destCoord();
        vec2 uv = (coordinate - extent.xy) / extent.zw;
        vec2 delta = uv - center;
        float aspect = extent.z / max(extent.w, 1.0);
        vec2 opticalDelta = vec2(delta.x, delta.y / max(aspect, 0.0001));
        float cornerRadius = length(vec2(0.5, 0.5 / max(aspect, 0.0001)));
        float radius = length(opticalDelta) / max(cornerRadius, 0.0001);
        float inner = mix(0.08, 0.70, clamp(falloff, 0.0, 1.0));
        float outer = mix(0.80, 1.02, clamp(falloff, 0.0, 1.0));
        float edge = smoothstep(inner, outer, radius);

        vec2 pixelCenter = extent.xy + center * extent.zw;
        vec2 pixelDelta = coordinate - pixelCenter;
        float pixelRadius = length(pixelDelta);
        vec2 radial = pixelRadius > 0.0001
            ? pixelDelta / pixelRadius
            : vec2(0.0);

        // This is Kromo's polar-space Gaussian expressed directly in Cartesian
        // coordinates: convolution follows the radial axis, and its radius grows
        // continuously as the image leaves the focus area. Forty-nine bilinear
        // samples eliminate the discrete echoes visible in the former 7-tap pass.
        float span = maximumOffset * edge;
        vec4 accumulated = vec4(0.0);
        float weightSum = 0.0;
        for (int index = -24; index <= 24; index++) {
            float position = float(index) / 24.0;
            float gaussianPosition = position * 2.75;
            float weight = exp(-0.5 * gaussianPosition * gaussianPosition);
            vec2 sampleCoordinate = coordinate + radial * position * span;
            accumulated += sample(
                source,
                samplerTransform(source, sampleCoordinate)
            ) * weight;
            weightSum += weight;
        }
        return accumulated / max(weightSum, 0.000001);
    }
    """#

    static let lensChromaticSource = #"""
    kernel vec4 lensChromatic(
        sampler blurredSource,
        vec4 extent,
        float falloff,
        float colorFringing,
        vec2 center
    ) {
        vec2 coordinate = destCoord();
        vec2 uv = (coordinate - extent.xy) / extent.zw;
        vec2 delta = uv - center;
        float aspect = extent.z / max(extent.w, 1.0);
        vec2 opticalDelta = vec2(delta.x, delta.y / max(aspect, 0.0001));
        float cornerRadius = length(vec2(0.5, 0.5 / max(aspect, 0.0001)));
        float radius = length(opticalDelta) / max(cornerRadius, 0.0001);
        float inner = mix(0.08, 0.70, clamp(falloff, 0.0, 1.0));
        float outer = mix(0.80, 1.02, clamp(falloff, 0.0, 1.0));
        float edge = smoothstep(inner, outer, radius);

        vec2 pixelCenter = extent.xy + center * extent.zw;
        vec2 pixelDelta = coordinate - pixelCenter;

        // Match Kromo's continuous channel enlargement: red remains anchored,
        // green expands slightly, and blue expands farther. Because this samples
        // the already-continuous radial convolution, no colored tap bands appear.
        float separation = clamp(colorFringing, 0.0, 2.0) * edge;
        float greenScale = 0.018 * separation;
        float blueScale = 0.044 * separation;
        vec2 greenCoordinate = coordinate - pixelDelta * (greenScale / (1.0 + greenScale));
        vec2 blueCoordinate = coordinate - pixelDelta * (blueScale / (1.0 + blueScale));

        vec4 anchored = sample(
            blurredSource,
            samplerTransform(blurredSource, coordinate)
        );
        float green = sample(
            blurredSource,
            samplerTransform(blurredSource, greenCoordinate)
        ).g;
        float blue = sample(
            blurredSource,
            samplerTransform(blurredSource, blueCoordinate)
        ).b;
        return vec4(max(vec3(anchored.r, green, blue), vec3(0.0)), anchored.a);
    }
    """#

    static let diffusionSource = #"""
    kernel vec4 diffuse(__sample source, __sample detail, __sample bloom, __sample wide, float amount, float bloomCharacter, float veil, float sourceBias, float warmth) {
        float sourceY = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
        float haloY = dot(bloom.rgb, vec3(0.2126, 0.7152, 0.0722));
        float strength = 1.0 - exp(-3.5 * clamp(amount, 0.0, 1.0));

        float kneeStart = mix(0.02, 0.35, clamp(sourceBias, 0.0, 1.0));
        float kneeEnd = min(1.5, kneeStart + 0.65);
        float flareGate = mix(0.30, 1.0, smoothstep(kneeStart, kneeEnd, haloY));

        // Black diffusion particles retain substantially more shadow density while
        // still allowing nearby practicals to spill into dark surroundings.
        float blackRetention = mix(0.62, 1.0, smoothstep(0.025, 0.25, sourceY));
        float nearWeight = strength * mix(0.18, 0.30, clamp(bloomCharacter, 0.0, 1.0));
        float bloomWeight = strength * mix(0.18, 0.46, clamp(bloomCharacter, 0.0, 1.0)) * flareGate * blackRetention;
        float wideWeight = strength * mix(0.08, 0.30, clamp(bloomCharacter, 0.0, 1.0)) * flareGate * blackRetention;
        float veilWeight = strength * clamp(veil, 0.0, 0.5) * 0.35 * blackRetention;

        float rawScatterWeight = nearWeight + bloomWeight + wideWeight + veilWeight;
        float scatterScale = min(1.0, 0.82 / max(rawScatterWeight, 0.0001));
        float scatteredWeight = rawScatterWeight * scatterScale;
        float sourceWeightFinal = 1.0 - scatteredWeight;
        vec3 warmthScale = vec3(1.0 + warmth * 0.08, 1.0, 1.0 - warmth * 0.04);
        vec3 scattered = (detail.rgb * nearWeight
            + bloom.rgb * warmthScale * bloomWeight
            + wide.rgb * warmthScale * (wideWeight + veilWeight)) * scatterScale;
        vec3 rgb = max(vec3(0.0), source.rgb * sourceWeightFinal + scattered);
        return vec4(rgb, source.a);
    }
    """#

    static let halationSource = #"""
    kernel vec4 halate(__sample source, __sample nearBlur, __sample middleBlur, __sample farBlur, float amount, float tail, float colorShift, float saturation, float greenLeakage) {
        float farWeight = mix(0.08, 0.26, clamp(tail, 0.0, 1.0));
        float middleWeight = 0.32;
        float nearWeight = 1.0 - middleWeight - farWeight;
        vec3 scattered = nearBlur.rgb * nearWeight + middleBlur.rgb * middleWeight + farBlur.rgb * farWeight;
        float redScatter = clamp(amount * mix(0.55, 0.92, saturation), 0.0, 0.85);
        float greenScatter = clamp(amount * greenLeakage * mix(0.8, 0.35, saturation) * mix(1.2, 0.75, colorShift), 0.0, 0.35);
        vec3 rgb;
        rgb.r = mix(source.r, scattered.r, redScatter);
        rgb.g = mix(source.g, scattered.g, greenScatter);
        rgb.b = source.b;
        return vec4(rgb, source.a);
    }
    """#

    static let landscapeGlowExtractionSource = #"""
    kernel vec4 landscapeGlowSource(__sample source) {
        const vec3 luma = vec3(0.2627002, 0.6779981, 0.0593017);
        float alpha = source.a;
        vec3 rgb = alpha > 0.000001
            ? max(source.rgb / alpha, vec3(0.0))
            : vec3(0.0);
        float y = max(dot(rgb, luma), 0.0);

        // A wide luminosity selection keeps upper midtones involved while making
        // direct light the dominant emitter. Dark structures contribute no shadow
        // halo to the blur, which is the main failure mode of a global Orton layer.
        float highlightGate = smoothstep(0.14, 0.78, y);
        float emission = highlightGate * mix(0.55, 1.0, highlightGate);
        return vec4(rgb * emission * alpha, alpha);
    }
    """#

    static let landscapeGlowSource = #"""
    kernel vec4 landscapeGlow(
        __sample source,
        __sample overallBlur,
        __sample middleBlur,
        __sample wideBlur,
        float amount,
        float shadowProtection,
        float detail
    ) {
        const vec3 luma = vec3(0.2627002, 0.6779981, 0.0593017);
        float sourceAlpha = source.a;
        vec3 sourceRGB = sourceAlpha > 0.000001
            ? max(source.rgb / sourceAlpha, vec3(0.0))
            : vec3(0.0);
        float sourceY = max(dot(sourceRGB, luma), 0.0);

        // Two highlight-only scales produce a luminous body and a long atmospheric
        // tail. Because shadows were excluded before the blur, this layer can add
        // light without averaging the source toward gray or creating dark halos.
        vec4 blurredPremultiplied = mix(middleBlur, wideBlur, 0.38);
        vec3 glowRGB = blurredPremultiplied.a > 0.000001
            ? max(blurredPremultiplied.rgb / blurredPremultiplied.a, vec3(0.0))
            : vec3(0.0);

        float normalizedAmount = (1.0 - exp(-2.2 * clamp(amount, 0.0, 1.0)))
            / (1.0 - exp(-2.2));

        // Rebuild the image from a broad color/tonal layer plus its original
        // high-frequency luminance residual. This is the full-frame Orton body:
        // cohesive low-frequency color and light without sacrificing crisp detail.
        vec3 overallRGB = overallBlur.a > 0.000001
            ? max(overallBlur.rgb / overallBlur.a, vec3(0.0))
            : vec3(0.0);
        float overallY = max(dot(overallRGB, luma), 0.000001);
        float lowStops = log2(overallY / 0.18);
        float contrastPosition = lowStops * 0.58;
        float contrastCurve = contrastPosition / (1.0 + abs(contrastPosition));
        float ortonLowY = 0.18 * exp2(
            lowStops + normalizedAmount * 0.16 * contrastCurve
        );
        float luminousMidtones = smoothstep(0.06, 0.38, overallY)
            * (1.0 - smoothstep(0.68, 1.08, overallY));
        ortonLowY *= 1.0 + normalizedAmount * 0.045 * luminousMidtones;

        float detailResidual = sourceY - overallY;
        float detailRetention = mix(0.82, 1.02, clamp(detail, 0.0, 1.0));
        float reconstructedY = max(
            0.0,
            mix(sourceY, ortonLowY + detailResidual * detailRetention, normalizedAmount)
        );
        vec3 tonedSource = sourceY > 0.000001
            ? sourceRGB * (reconstructedY / sourceY)
            : vec3(0.0);
        vec3 ortonColor = overallRGB * (reconstructedY / overallY);
        float colorMeld = normalizedAmount
            * mix(0.20, 0.08, clamp(detail, 0.0, 1.0));
        vec3 baseRGB = mix(tonedSource, ortonColor, colorMeld);

        // Protect a progressively wider receiving shadow range without a hard mask.
        // Glow remains strongest beside light, then eases near white to retain sky
        // gradients and illuminated cloud structure.
        float shadowKnee = mix(0.008, 0.15, clamp(shadowProtection, 0.0, 1.0));
        float shadowGate = smoothstep(shadowKnee * 0.35, shadowKnee + 0.16, sourceY);
        float highlightProtection = 1.0 - 0.48 * smoothstep(0.72, 1.10, sourceY);
        float glowWeight = normalizedAmount * 0.22 * shadowGate * highlightProtection;
        float headroom = 1.0 - smoothstep(0.58, 1.08, sourceY);
        vec3 rgb = max(
            vec3(0.0),
            baseRGB + glowRGB * glowWeight * mix(0.42, 1.0, headroom)
        );

        // Pull only out-of-range chroma toward neutral. This retains extended
        // luminance for the output transform and avoids channel-clipped sunsets.
        float outputY = max(dot(rgb, luma), 0.000001);
        float minimum = min(rgb.r, min(rgb.g, rgb.b));
        float maximum = max(rgb.r, max(rgb.g, rgb.b));
        float lowScale = minimum < 0.0 ? outputY / max(outputY - minimum, 0.000001) : 1.0;
        float availableHighlight = max(1.08 - outputY, 0.0);
        float colorExcursion = max(maximum - outputY, 0.0);
        float highScale = colorExcursion > availableHighlight
            ? availableHighlight / max(colorExcursion, 0.000001)
            : 1.0;
        rgb = mix(vec3(outputY), rgb, clamp(min(lowScale, highScale), 0.0, 1.0));
        return vec4(rgb * sourceAlpha, sourceAlpha);
    }
    """#

}

extension FilmRenderer {
    static let grainHashSource = #"""
    float filmHash(vec2 p, float seed) {
        // Mix bounded fractional values instead of amplifying GPU-dependent sin
        // approximations. Split the seed so large phases do not swallow pixel
        // differences before the mix. Exact patterns may still vary by GPU.
        vec2 phase = vec2(mod(seed, 1024.0), floor(seed / 1024.0));
        vec3 h = fract(vec3(p.x + phase.x, p.y + phase.y, p.x + phase.y)
            * vec3(0.1031, 0.1030, 0.0973));
        h += dot(h, h.yzx + 33.33);
        return fract((h.x + h.y) * h.z);
    }
    """#

}

private extension FilmRenderer {
    static let grainSource = grainHashSource + "\n" + #"""
    float filmNoise(vec2 p, float seed) {
        vec2 cell = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = filmHash(cell, seed);
        float b = filmHash(cell + vec2(1.0, 0.0), seed);
        float c = filmHash(cell + vec2(0.0, 1.0), seed);
        float d = filmHash(cell + vec2(1.0, 1.0), seed);
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    float filmTriangularNoise(vec2 pixel, float seed) {
        float a = filmHash(pixel, seed);
        float b = filmHash(pixel + vec2(37.0, 17.0), seed + 113.0);
        float c = filmHash(pixel + vec2(11.0, 53.0), seed + 271.0);
        // Match the contrast of the former interpolated field while giving the
        // samples a softer, film-density-like distribution.
        return (a + b + c - 1.5) * 0.36;
    }

    float filmParticleNoise(vec2 coordinate, vec2 pixel, float particlePixels, float acutance, float seed) {
        // At normal still-image grain sizes a fresh, distribution-shaped sample per
        // output pixel avoids the lattice and cloudy clumps produced by interpolated
        // value noise. As particles become visibly larger, gently blend in two
        // differently rotated fields so the correlation remains organic rather than
        // aligning to a square grid.
        float independent = filmTriangularNoise(pixel, seed);
        vec2 rotatedA = vec2(
            coordinate.x * 0.819152 - coordinate.y * 0.573576,
            coordinate.x * 0.573576 + coordinate.y * 0.819152
        );
        vec2 rotatedB = vec2(
            coordinate.x * 0.422618 + coordinate.y * 0.906308,
            -coordinate.x * 0.906308 + coordinate.y * 0.422618
        );
        float fieldA = filmNoise(rotatedA + vec2(19.7, 7.3), seed + 41.0) - 0.5;
        float fieldB = filmNoise(rotatedB * 1.173 + vec2(5.1, 23.9), seed + 197.0) - 0.5;
        float correlated = (fieldA * 0.58 + fieldB * 0.42) * 1.52;
        // Start resolving particle scale below one output pixel. This is important
        // for the live preview, where physically small grains would otherwise all
        // collapse to the same single-pixel pattern.
        // Acutance changes how distinctly individual grains resolve: lower values
        // favor the softly correlated dye-cloud fields, while higher values retain
        // more independent, high-frequency particles. Center the offset around the
        // recipe default so existing looks keep their morphology.
        float baseCorrelation = smoothstep(0.22, 1.55, particlePixels);
        float acutanceOffset = mix(0.38, -0.28, clamp(acutance, 0.0, 1.0));
        float correlation = clamp(baseCorrelation + acutanceOffset, 0.0, 1.0);
        // Independent samples have variance 0.0324; the two smoothstep fields
        // have approximately 0.05449. Normalize the blend to the latter so
        // resolution changes its structure without also changing Amount.
        float independentWeight = 1.0 - correlation;
        float blendVariance = independentWeight * independentWeight * 0.0324
            + correlation * correlation * 0.05449;
        return mix(independent, correlated, correlation) * sqrt(0.05449 / blendVariance);
    }

    kernel vec4 grain(__sample source, __sample densityGuide, vec4 extent, float amount, float particlePixels, float acutance, float variation, float chroma, float shadowResponse, float highlightResponse, float seed) {
        vec2 coordinate = (destCoord() - extent.xy) / max(particlePixels, 0.5);
        vec2 pixel = floor(destCoord());
        float primary = filmParticleNoise(coordinate, pixel, particlePixels, acutance, seed);
        float variationAmount = clamp(variation, 0.0, 1.0);
        float alternateScale = mix(1.0, 0.52, variationAmount);
        float varied = filmParticleNoise(
            coordinate * alternateScale + vec2(13.7, 29.1),
            pixel + vec2(47.0, 31.0),
            particlePixels / alternateScale,
            acutance,
            seed + 431.0
        );
        // Size Variation introduces a genuinely broader second population instead
        // of merely nudging the original scale. Normalize both blends so these
        // character controls reshape grain without acting like hidden Amount knobs.
        float variationMix = variationAmount * 0.44;
        float variationNormalization = 1.0 / sqrt(
            max(0.2, (1.0 - variationMix) * (1.0 - variationMix) + variationMix * variationMix)
        );
        float densityNoise = mix(primary, varied, variationMix) * variationNormalization;

        vec4 straightSource = unpremultiply(source);
        vec4 straightGuide = unpremultiply(densityGuide);
        // The renderer works in linear Rec. 2020. Shape visibility in perceptual
        // tones so the shadow peak actually lands in visible darker midtones.
        float linearLuminance = clamp(
            dot(max(straightGuide.rgb, vec3(0.0)), vec3(0.2627, 0.6780, 0.0593)),
            0.0,
            1.0
        );
        float localLuminance = linearLuminance <= 0.0031308
            ? linearLuminance * 12.92
            : 1.055 * pow(linearLuminance, 1.0 / 2.4) - 0.055;
        float shadowWeight = pow(1.0 - localLuminance, 0.72);
        float endpointResponse = mix(highlightResponse, shadowResponse, shadowWeight);

        // A broad darker-midtone peak, with a quiet toe and an earlier shoulder,
        // avoids both noisy blocked blacks and conspicuous grain in bright skies.
        // This is a perceptual film-look model, not a stock-specific simulation.
        float toeTransition = smoothstep(0.04, 0.40, localLuminance);
        float toeCompression = mix(0.18, 1.0, toeTransition);
        float shoulderTransition = smoothstep(0.50, 1.0, localLuminance);
        float shoulderCompression = mix(1.0, 0.18, shoulderTransition);
        float tonalResponse = endpointResponse * toeCompression * shoulderCompression * 1.4;
        float sigma = amount * tonalResponse * 0.34;
        float densityDelta = densityNoise * sigma;
        // Cancel the mean lift from exponentiating zero-mean density noise. The
        // normalized field variance is 0.05449: 0.5 * ln(10) * variance.
        float densityCompensation = 0.06273 * sigma * sigma;
        float luminanceScale = exp2(-(densityDelta + densityCompensation) * 3.321928);

        vec3 chromaNoise = vec3(
            filmParticleNoise(coordinate * 0.91 + vec2(3.1, 7.7), pixel + vec2(7.0, 61.0), particlePixels / 0.91, acutance, seed + 151.0),
            filmParticleNoise(coordinate * 1.07 + vec2(11.2, 2.4), pixel + vec2(59.0, 13.0), particlePixels / 1.07, acutance, seed + 263.0),
            filmParticleNoise(coordinate * 0.83 + vec2(5.8, 13.9), pixel + vec2(23.0, 79.0), particlePixels / 0.83, acutance, seed + 379.0)
        );
        // Independent dye-layer variation is separated from the shared silver-density
        // component and made luminance-neutral so Chroma changes color texture rather
        // than overall grain contrast.
        chromaNoise -= vec3(dot(chromaNoise, vec3(0.2126, 0.7152, 0.0722)));
        // The separate dye records are least convincing when they sparkle in blocked
        // shadows or nearly white highlights. Let their small differences live mostly
        // in the printable density range while the shared silver-density texture
        // continues softly into the extremes.
        float dyeToe = smoothstep(0.15, 0.48, localLuminance);
        float dyeShoulder = 1.0 - smoothstep(0.70, 0.97, localLuminance);
        float dyeCloudResponse = mix(0.16, 1.0, dyeToe * dyeShoulder);
        float chromaStrength = amount * clamp(chroma, 0.0, 1.0) * tonalResponse * dyeCloudResponse * 0.50;
        vec3 colorScale = max(vec3(0.05), vec3(1.0) + chromaNoise * chromaStrength);
        vec3 rgb = max(vec3(0.0), straightSource.rgb * luminanceScale * colorScale);
        return premultiply(vec4(rgb, straightSource.a));
    }
    """#
}
