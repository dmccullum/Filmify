import CoreImage
import Foundation
import Testing
@testable import GranularCore

@Test func builtInRecipesHaveStableIdentifiersAndRanges() {
    #expect(FilmRecipe.builtIns.map(\.name) == ["Clean 120", "Classic 35", "Extra 35", "Soft 16", "Raw"])
    #expect(Set(FilmRecipe.builtIns.map(\.id)).count == FilmRecipe.builtIns.count)

    for recipe in FilmRecipe.builtIns {
        #expect(recipe.tone == FilmToneSettings(isEnabled: false))
        #expect((0 ... 1).contains(recipe.lightShaping.amountStops))
        #expect(recipe.lensBlur.isEnabled == false)
        #expect((0 ... 1).contains(recipe.lensBlur.amount))
        #expect((0 ... 1).contains(recipe.diffusion.amount))
        #expect((0 ... 1).contains(recipe.halation.amount))
        #expect(recipe.landscapeGlow.isEnabled == false)
        #expect((0 ... 1).contains(recipe.landscapeGlow.amount))
        #expect((0 ... 1).contains(recipe.grain.amount))
        #expect(recipe.grain.grainSize > 0)
    }
}

@Test func rawRecipeLeavesThePhotoAlone() throws {
    let recipe = try #require(FilmRecipe.builtIns.first { $0.id == "raw" })

    #expect(!recipe.tone.isEnabled)
    #expect(!recipe.lightShaping.isEnabled)
    #expect(!recipe.lensBlur.isEnabled)
    #expect(!recipe.diffusion.isEnabled)
    #expect(!recipe.halation.isEnabled)
    #expect(!recipe.landscapeGlow.isEnabled)
    #expect(!recipe.grain.isEnabled)
}

@Test func landscapeGlowDefaultsAreRestrainedAndDisabled() {
    let settings = LandscapeGlowSettings()

    #expect(settings.isEnabled == false)
    #expect(settings.amount == 0.25)
    #expect(settings.glowSize == 0.5)
    #expect(settings.shadowProtection == 0.72)
    #expect(settings.detail == 0.7)
}

@Test func recipesSavedBeforeLandscapeGlowDecodeWithTheEffectDisabled() throws {
    let legacy = LegacyFilmRecipe(
        id: "legacy",
        name: "Legacy Recipe",
        tone: .init(isEnabled: false),
        lightShaping: .init(isEnabled: false),
        lensBlur: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )
    let data = try JSONEncoder().encode(legacy)
    let decoded = try JSONDecoder().decode(FilmRecipe.self, from: data)

    #expect(decoded.id == legacy.id)
    #expect(decoded.name == legacy.name)
    #expect(decoded.landscapeGlow == LandscapeGlowSettings())
}

@Test func landscapeGlowSettingsRoundTripWithRecipes() throws {
    var recipe = FilmRecipe.classic35
    recipe.landscapeGlow = .init(
        isEnabled: true,
        amount: 0.63,
        glowSize: 0.82,
        shadowProtection: 0.41,
        detail: 0.77
    )

    let data = try JSONEncoder().encode(recipe)
    let decoded = try JSONDecoder().decode(FilmRecipe.self, from: data)

    #expect(decoded == recipe)
}

@Test func recipeCanistersRoundTripAndDefaultToAutomatic() throws {
    let legacy = try JSONDecoder().decode(FilmRecipe.self, from: JSONEncoder().encode(LegacyFilmRecipe(
        id: "legacy",
        name: "Legacy Recipe",
        tone: .init(isEnabled: false),
        lightShaping: .init(isEnabled: false),
        lensBlur: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )))
    #expect(legacy.canister == nil)

    var recipe = FilmRecipe.classic35
    recipe.canister = "ember"
    let decoded = try JSONDecoder().decode(FilmRecipe.self, from: JSONEncoder().encode(recipe))
    #expect(decoded.canister == "ember")
}

@Test func classic35UsesTheCIHBalance() {
    let recipe = FilmRecipe.classic35

    #expect(recipe.tone == FilmToneSettings(isEnabled: false))
    #expect(recipe.lightShaping.amountStops == 0.25)
    #expect(recipe.diffusion.amount == 0.06)
    #expect(recipe.halation.amount == 0.15)
    #expect(recipe.grain.amount == 0.17)
}

@Test func allNamedColorStocksLoadAsCoreImageCubes() throws {
    for stock in FilmStockID.allCases where stock.resourceName != nil {
        let cube = try FilmStockLUTLoader.load(stock)
        #expect(cube.dimension == 33)
        #expect(cube.data.count == 33 * 33 * 33 * 4 * MemoryLayout<Float>.size)
    }
}

@Test func colorStockAmountIsNeutralAtZeroAndDistinctAtFullStrength() throws {
    let renderer = try FilmRenderer()
    let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
    let source = CIImage(color: .init(red: 0.42, green: 0.24, blue: 0.10, alpha: 1))
        .cropped(to: extent)
    var recipe = FilmRecipe(
        id: "stock-test",
        name: "Stock Test",
        tone: .init(stock: .portra400, stockAmount: 0),
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )

    let sourcePixels = renderFloatPixels(source, extent: extent)
    let neutralPixels = renderFloatPixels(try renderer.render(source, recipe: recipe), extent: extent)
    #expect(abs(sourcePixels[0] - neutralPixels[0]) < 0.000_001)
    #expect(abs(sourcePixels[1] - neutralPixels[1]) < 0.000_001)
    #expect(abs(sourcePixels[2] - neutralPixels[2]) < 0.000_001)

    recipe.tone.stockAmount = 1
    let portraPixels = renderFloatPixels(try renderer.render(source, recipe: recipe), extent: extent)
    recipe.tone.stockAmount = 2
    let overcookedPortraPixels = renderFloatPixels(
        try renderer.render(source, recipe: recipe),
        extent: extent
    )
    recipe.tone.stock = .ektar100
    recipe.tone.stockAmount = 1
    let ektarPixels = renderFloatPixels(try renderer.render(source, recipe: recipe), extent: extent)

    #expect(colorDistance(sourcePixels, portraPixels) > 0.01)
    #expect(
        colorDistance(sourcePixels, overcookedPortraPixels)
            > colorDistance(sourcePixels, portraPixels) * 1.5
    )
    #expect(colorDistance(portraPixels, ektarPixels) > 0.0075)
}

@Test func colorStockAmountDefaultsToOneWithAnOvercookMaximumOfTwo() {
    #expect(FilmToneSettings().stockAmount == 1)
    #expect(FilmToneSettings.maximumStockAmount == 2)
}

@Test func filmStocksCarryTheirOwnRestrainedContrast() throws {
    let renderer = try FilmRenderer()
    let sourceContrast = Float(0.68 - 0.12)

    func contrast(_ stock: FilmStockID) throws -> Float {
        let low = try renderStockPatches(renderer, stock: stock, colors: [[0.12, 0.12, 0.12]])
        let high = try renderStockPatches(renderer, stock: stock, colors: [[0.68, 0.68, 0.68]])
        return pixelLuminance(high[0]) - pixelLuminance(low[0])
    }

    for stock in FilmStockID.allCases where stock != .none {
        let output = try contrast(stock)
        #expect(output > sourceContrast * 0.70, "\(stock.name)")
        #expect(output < sourceContrast * 1.60, "\(stock.name)")
    }

    // Slide film's extra density shows as deeper shadows below middle gray.
    func shadowDepth(_ stock: FilmStockID) throws -> Float {
        let shadow = try renderStockPatches(renderer, stock: stock, colors: [[0.03, 0.03, 0.03]])
        return pixelLuminance(shadow[0])
    }
    #expect(try shadowDepth(.velvia100F) < shadowDepth(.portra400) * 0.85)
}

@Test func spectralStocksKeepMiddleGrayNearMiddleGray() throws {
    // Fitted characters keep their reference's exposure shift on purpose.
    let renderer = try FilmRenderer()
    for stock in FilmStockID.allCases where stock.resourceName != nil {
        let gray = try renderStockPatches(renderer, stock: stock, colors: [[0.18, 0.18, 0.18]])[0]
        let stops = log2(Double(pixelLuminance(gray)) / 0.18)
        #expect(abs(stops) < 0.34, "\(stock.name) moves middle gray \(stops) stops")
    }
}

@Test func everyFilmStockLooksDistinct() throws {
    let renderer = try FilmRenderer()
    let patches: [[Float]] = [
        [0.40, 0.24, 0.17], [0.20, 0.11, 0.07], [0.12, 0.18, 0.06], [0.05, 0.10, 0.03],
        [0.10, 0.20, 0.45], [0.30, 0.40, 0.55], [0.55, 0.08, 0.06], [0.60, 0.45, 0.06],
        [0.08, 0.30, 0.30], [0.25, 0.10, 0.35], [0.04, 0.04, 0.04], [0.18, 0.18, 0.18],
        [0.60, 0.60, 0.60]
    ]
    let stocks = FilmStockID.allCases.filter { $0 != .none }
    let looks = try stocks.map { stock in
        try renderStockPatches(renderer, stock: stock, colors: patches).map(oklab)
    }

    var closest = (distance: Float.greatestFiniteMagnitude, pair: "")
    for first in stocks.indices {
        for second in stocks.indices where second > first {
            let distance = zip(looks[first], looks[second])
                .map { labDistance($0, $1) }
                .reduce(0, +) / Float(patches.count)
            if distance < closest.distance {
                closest = (distance, "\(stocks[first].name) / \(stocks[second].name)")
            }
        }
    }
    #expect(closest.distance > 0.009, "Closest stocks: \(closest.pair) at \(closest.distance)")
}

@Test func blackAndWhiteStocksStayNeutralWhenOvercooked() throws {
    let renderer = try FilmRenderer()
    for stock in FilmStockID.allCases where stock.isMonochrome {
        for amount in [1.0, 2.0] {
            let pixel = try renderStockPatches(
                renderer, stock: stock, amount: amount, colors: [[0.55, 0.20, 0.08]]
            )[0]
            #expect(channelSpread(pixel) < 0.002, "\(stock.name) at \(amount)")
        }
    }
}

@Test func retiredAndUnknownStocksDecodeWithoutLosingTheRecipe() throws {
    func decode(_ stock: String) throws -> FilmStockID {
        var recipe = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(FilmRecipe.classic35)
        ) as! [String: Any]
        var tone = recipe["tone"] as! [String: Any]
        tone["stock"] = stock
        recipe["tone"] = tone
        let data = try JSONSerialization.data(withJSONObject: recipe)
        return try JSONDecoder().decode(FilmRecipe.self, from: data).tone.stock
    }

    #expect(try decode("portra160") == .portra400)
    #expect(try decode("superiaReala") == .superia400)
    #expect(try decode("velvia50") == .velvia100F)
    #expect(try decode("ektachrome100D") == .e100G)
    #expect(try decode("hp5") == .hp5)
    #expect(try decode("someFutureStock") == FilmStockID.none)
}

@Test func everyFilmStockBelongsToAFamilyAndDescribesItself() {
    for family in FilmStockFamily.allCases {
        #expect(!family.stocks.isEmpty)
    }
    for stock in FilmStockID.allCases where stock != .none {
        #expect(stock.family != nil)
        #expect(!stock.vibe.isEmpty)
        #expect(!stock.name.contains("/"))
    }
}

@Test func stockThumbnailsRenderSmallPreviews() async throws {
    let service = try ImageProcessingService()
    for stock in [FilmStockID.none, .velvia100F, .triX400] {
        let image = try await service.renderStockThumbnail(
            sourceURL: nil, tone: .init(), stock: stock, maximumPixelSize: 96
        )
        #expect(max(image.width, image.height) <= 96)
    }
}

@Test func classic35DefaultsMatchCalibratedRecipe() {
    let recipe = FilmRecipe.classic35

    #expect(recipe.lightShaping.amountStops == 0.25)
    #expect(recipe.diffusion.amount == 0.06)
    #expect(recipe.halation.amount == 0.15)
    #expect(recipe.grain.amount == 0.17)
    #expect(recipe.grain.grainSize == 10)
}

@Test func clean120DefaultsMatchReferenceSettings() throws {
    let recipe = try #require(FilmRecipe.builtIns.first { $0.id == "clean-120" })

    #expect(recipe.lightShaping.amountStops == 0.10)
    #expect(recipe.lightShaping.focus == 0.68)
    #expect(recipe.diffusion.amount == 0.10)
    #expect(recipe.diffusion.bloom == 0.20)
    #expect(recipe.halation.amount == 0.10)
    #expect(recipe.halation.spillRadius == 0.20)
    #expect(recipe.grain.amount == 0.15)
    #expect(abs(recipe.grain.grainSize - 3.86) < 0.000_001)
}

@Test func extra35PreservesThePriorClassic35RendererStrengths() throws {
    let recipe = try #require(FilmRecipe.builtIns.first { $0.id == "extra-35" })

    #expect(FilmRenderer.mappedSpotlightAmount(recipe.lightShaping.amountStops) == 1.0)
    #expect(FilmRenderer.mappedOpticalAmount(recipe.diffusion.amount) == 0.20)
    #expect(FilmRenderer.mappedOpticalAmount(recipe.halation.amount) == 0.50)
    #expect(abs(FilmRenderer.mappedGrainAmount(recipe.grain.amount) - 1.056) < 0.000_001)
}

@Test func halationUsesNormalizedAmountsWithoutChangingRecipeStrengths() throws {
    #expect(HalationSettings.maximumAmount == 1)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "clean-120" }).halation.amount == 0.10)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "extra-35" }).halation.amount == 0.25)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "soft-16" }).halation.amount == 0.40)
}

@Test func diffusionUsesNormalizedAmountsWithoutChangingRecipeStrengths() throws {
    #expect(DiffusionSettings.maximumAmount == 1)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "clean-120" }).diffusion.amount == 0.10)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "extra-35" }).diffusion.amount == 0.10)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "soft-16" }).diffusion.amount == 0.40)
}

@Test func expandedOpticalAmountsUseAProgressiveSecondPass() {
    #expect(FilmRenderer.opticalPassAmounts(for: FilmRenderer.mappedOpticalAmount(0.25)) == [0.5])
    #expect(FilmRenderer.opticalPassAmounts(for: FilmRenderer.mappedOpticalAmount(0.50)) == [1.0])
    #expect(FilmRenderer.opticalPassAmounts(for: FilmRenderer.mappedOpticalAmount(0.75)) == [1.0, 0.5])
    #expect(FilmRenderer.opticalPassAmounts(for: FilmRenderer.mappedOpticalAmount(1.00)) == [1.0, 1.0])
}

@Test func newOpticalMaximumsAreVisiblyStrongerThanTheFormerMaximums() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 256)
    let black = CIImage(color: .init(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
    let practical = CIImage(color: .init(red: 1, green: 1, blue: 1, alpha: 1))
        .cropped(to: CGRect(x: 120, y: 120, width: 16, height: 16))
    let source = practical.composited(over: black)
    let renderer = try FilmRenderer()

    let diffusionAtOne = renderFloatPixels(
        try renderer.render(source, recipe: opticalStrengthRecipe(diffusionAmount: 0.5)),
        extent: extent
    )
    let diffusionAtTwo = renderFloatPixels(
        try renderer.render(source, recipe: opticalStrengthRecipe(diffusionAmount: 1)),
        extent: extent
    )
    let halationAtOne = renderFloatPixels(
        try renderer.render(source, recipe: opticalStrengthRecipe(halationAmount: 0.5)),
        extent: extent
    )
    let halationAtTwo = renderFloatPixels(
        try renderer.render(source, recipe: opticalStrengthRecipe(halationAmount: 1)),
        extent: extent
    )
    let haloPixel = (128 * 256 + 112) * 4

    #expect(diffusionAtTwo[haloPixel] > diffusionAtOne[haloPixel] * 1.05)
    #expect(halationAtTwo[haloPixel] > halationAtOne[haloPixel] * 1.05)
}

@Test func soft16GrainDefaultsMatchReferenceSettings() throws {
    let recipe = try #require(FilmRecipe.builtIns.first { $0.id == "soft-16" })

    #expect(recipe.lightShaping.amountStops == 0.50)
    #expect(recipe.lightShaping.focus == 0.48)
    #expect(recipe.diffusion.amount == 0.40)
    #expect(recipe.diffusion.bloom == 0.50)
    #expect(recipe.halation.amount == 0.40)
    #expect(recipe.halation.spillRadius == 0.50)
    #expect(recipe.grain.amount == 0.25)
    #expect(recipe.grain.grainSize == 30)
    #expect(recipe.grain.acutance == 0.42)
    #expect(recipe.grain.sizeVariation == 0.50)
    #expect(recipe.grain.chroma == 0.98)
    #expect(recipe.grain.shadowResponse == 0.72)
    #expect(recipe.grain.highlightResponse == 0.28)
}

@Test func grainAmountUsesTheCalibratedIntensityScale() {
    #expect(FilmRenderer.mappedGrainAmount(0) == 0)
    #expect(abs(FilmRenderer.mappedGrainAmount(0.25) - 1.056) < 0.000_001)
    #expect(abs(FilmRenderer.mappedGrainAmount(1) - 4.224) < 0.000_001)
}

@Test func grainRandomFieldHasNoStrongDirectionalCorrelation() throws {
    // Exercise the actual GPU hash at photo-sized coordinates, including large
    // seeds. Small images alone can miss the diagonal bands seen in exports.
    let kernel = try #require(CIColorKernel(source: FilmRenderer.grainHashSource + "\n" + """
        kernel vec4 randomField(float seed) {
            float value = filmHash(floor(destCoord()), seed);
            return vec4(value, value, value, 1.0);
        }
        """))
    let side = 256
    for origin in [CGPoint.zero, CGPoint(x: 5500, y: 3500)] {
        let extent = CGRect(origin: origin, size: CGSize(width: side, height: side))
        for seed: UInt32 in [1234, 999_999, UInt32.max] {
            let field = try #require(kernel.apply(
                extent: extent, arguments: [FilmRenderer.mappedGrainSeed(seed)]
            ))
            let pixels = renderFloatPixels(field, extent: extent)
            let values = stride(from: 0, to: pixels.count, by: 4).map { Double(pixels[$0]) }
            let mean = values.reduce(0, +) / Double(values.count)
            var variance = 0.0
            for value in values {
                let delta = value - mean
                variance += delta * delta
            }
            variance /= Double(values.count)
            #expect(abs(mean - 0.5) < 0.02)
            #expect(variance > 0.07 && variance < 0.095)
            for (dx, dy) in [(1, 0), (0, 1), (1, 1), (-1, 1), (3, 1), (1, 3), (8, 0), (0, 8)] {
                var covariance = 0.0
                var count = 0
                for y in 0 ..< side - dy {
                    for x in max(0, -dx) ..< min(side, side - dx) {
                        covariance += (values[y * side + x] - mean)
                            * (values[(y + dy) * side + x + dx] - mean)
                        count += 1
                    }
                }
                #expect(abs(covariance / Double(count) / variance) < 0.05)
            }
        }
    }
}

@Test func spotlightAmountUsesTheExpandedIntensityScale() {
    #expect(FilmRenderer.mappedSpotlightAmount(0) == 0)
    #expect(FilmRenderer.mappedSpotlightAmount(0.5) == 2)
    #expect(FilmRenderer.mappedSpotlightAmount(1) == 4)
}

@Test func lensBlurStartsAtTheFormerMaximumAndAllowsOvercooking() {
    #expect(FilmRenderer.mappedLensBlurAmount(0) == 0)
    #expect(FilmRenderer.mappedLensBlurAmount(0.25) == 1)
    #expect(FilmRenderer.mappedLensBlurAmount(1) == 4)
}

@Test func lensBlurRGBSeparationDoublesItsPreviousRange() {
    #expect(FilmRenderer.mappedLensBlurRGBSeparation(0) == 0)
    #expect(FilmRenderer.mappedLensBlurRGBSeparation(0.5) == 1)
    #expect(FilmRenderer.mappedLensBlurRGBSeparation(1) == 2)
}

@Test func viewerZoomUsesActualImageScaleAndFitGeometry() {
    let fit = ViewerZoomMath.fitScale(
        imageWidth: 4_000,
        imageHeight: 3_000,
        viewportWidth: 1_000,
        viewportHeight: 800
    )

    #expect(abs(fit - 0.238) < 0.000_001)
    #expect(ViewerZoomMath.zoomedIn(from: fit) == 0.25)
    #expect(ViewerZoomMath.zoomedOut(from: fit) == 0.125)
    #expect(ViewerZoomMath.zoomedIn(from: 1) == 2)
    #expect(ViewerZoomMath.zoomedOut(from: 1) == 0.5)
    #expect(ViewerZoomMath.zoomedOut(from: 1.25) == 1)
}

@Test func viewerZoomSliderAndPanClampingAreStable() {
    let scale = 0.237
    let position = ViewerZoomMath.sliderPosition(forScale: scale)

    #expect(abs(ViewerZoomMath.scale(forSliderPosition: position) - scale) < 0.000_001)
    #expect(ViewerZoomMath.clampedPanOffset(900, displayLength: 1_600, viewportLength: 1_000) == 300)
    #expect(ViewerZoomMath.clampedPanOffset(-900, displayLength: 1_600, viewportLength: 1_000) == -300)
    #expect(ViewerZoomMath.clampedPanOffset(50, displayLength: 800, viewportLength: 1_000) == 0)
}

@Test func grainChromaProducesVisibleLuminanceNeutralColorVariation() throws {
    let extent = CGRect(x: 0, y: 0, width: 192, height: 192)
    let source = CIImage(color: .init(red: 0.42, green: 0.42, blue: 0.42, alpha: 1))
        .cropped(to: extent)
    let monochromeRecipe = grainTestRecipe(chroma: 0)
    let chromaticRecipe = grainTestRecipe(chroma: 1)
    let renderer = try FilmRenderer()

    let monochromePixels = renderFloatPixels(try renderer.render(source, recipe: monochromeRecipe), extent: extent)
    let chromaticPixels = renderFloatPixels(try renderer.render(source, recipe: chromaticRecipe), extent: extent)
    let monochromeEnergy = meanChromaEnergy(monochromePixels)
    let chromaticEnergy = meanChromaEnergy(chromaticPixels)

    #expect(monochromeEnergy < 0.000_001)
    #expect(chromaticEnergy > 0.000_2)
}

@Test func grainDensityResponseCompressesTheToeAndHighlightShoulder() throws {
    let extent = CGRect(x: 0, y: 0, width: 192, height: 192)
    let renderer = try FilmRenderer()
    let recipe = grainTestRecipe(chroma: 0)

    func relativeGrain(at luminance: CGFloat) throws -> Double {
        let source = CIImage(
            color: .init(red: luminance, green: luminance, blue: luminance, alpha: 1)
        ).cropped(to: extent)
        let pixels = renderFloatPixels(try renderer.render(source, recipe: recipe), extent: extent)
        return luminanceCoefficientOfVariation(pixels)
    }

    let deepShadow = try relativeGrain(at: 0.02)
    let middleDensity = try relativeGrain(at: 0.45)
    let brightHighlight = try relativeGrain(at: 0.95)

    #expect(middleDensity > deepShadow * 1.5)
    #expect(middleDensity > brightHighlight * 2)
}

@Test func grainMorphologyControlsRemainVisibleAtPreviewScale() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 256)
    let source = CIImage(color: .init(red: 0.42, green: 0.42, blue: 0.42, alpha: 1))
        .cropped(to: extent)
    let renderer = try FilmRenderer()

    func render(
        grainSize: Double,
        acutance: Double,
        variation: Double
    ) throws -> [Float] {
        let recipe = FilmRecipe(
            id: "grain-morphology-test",
            name: "Grain Morphology Test",
            lightShaping: .init(isEnabled: false),
            diffusion: .init(isEnabled: false),
            halation: .init(isEnabled: false),
            grain: .init(
                amount: 0.5,
                grainSize: grainSize,
                acutance: acutance,
                sizeVariation: variation,
                chroma: 0,
                seed: 1_234
            )
        )
        return renderFloatPixels(try renderer.render(source, recipe: recipe), extent: extent)
    }

    let fine = try render(grainSize: 3, acutance: 0, variation: 0)
    let coarse = try render(grainSize: 100, acutance: 0, variation: 0)
    let soft = try render(grainSize: 22, acutance: 0, variation: 0)
    let crisp = try render(grainSize: 22, acutance: 1, variation: 0)
    let uniform = try render(grainSize: 14, acutance: 0.5, variation: 0)
    let varied = try render(grainSize: 14, acutance: 0.5, variation: 1)

    #expect(meanAbsoluteLuminanceDifference(fine, coarse) > 0.01)
    #expect(meanAbsoluteLuminanceDifference(soft, crisp) > 0.01)
    #expect(meanAbsoluteLuminanceDifference(uniform, varied) > 0.01)
}

@Test func grainStrengthRemainsStableAcrossImageResolutions() throws {
    let renderer = try FilmRenderer()
    let sampleExtent = CGRect(x: 0, y: 0, width: 256, height: 256)
    for size in [3.86, 10.0, 24.1] {
        var native: [Double] = []
        var fitted: [Double] = []
        for width in [1600, 3000, 6000] {
            let extent = CGRect(x: 0, y: 0, width: width, height: width * 2 / 3)
            let source = CIImage(color: .init(red: 0.42, green: 0.42, blue: 0.42, alpha: 1))
                .cropped(to: extent)
            var recipe = grainTestRecipe(chroma: 0)
            recipe.grain.grainSize = size
            let rendered = try renderer.render(source, recipe: recipe)
            native.append(luminanceCoefficientOfVariation(renderFloatPixels(rendered, extent: sampleExtent)))
            let preview = try renderer.render(source, recipe: recipe, previewMaximumDimension: 1600)
            #expect(preview.extent.width == 1600)
            fitted.append(luminanceCoefficientOfVariation(renderFloatPixels(preview, extent: sampleExtent)))
        }
        #expect(native.max()! / native.min()! < 1.2)
        #expect(fitted.max()! / fitted.min()! < 1.2)
    }
}

@Test func fullRangeSavedGrainSeedsRetainTextureWithoutChangingMeanDensity() throws {
    let extent = CGRect(x: 0, y: 0, width: 192, height: 192)
    let source = CIImage(color: .init(red: 0.42, green: 0.42, blue: 0.42, alpha: 1))
        .cropped(to: extent)
    let renderer = try FilmRenderer()
    var normalRecipe = grainTestRecipe(chroma: 0)
    normalRecipe.grain.seed = 2_016
    var maximumSeedRecipe = normalRecipe
    maximumSeedRecipe.grain.seed = UInt32.max

    let normal = renderFloatPixels(try renderer.render(source, recipe: normalRecipe), extent: extent)
    let maximumSeed = renderFloatPixels(
        try renderer.render(source, recipe: maximumSeedRecipe),
        extent: extent
    )

    #expect(luminanceCoefficientOfVariation(maximumSeed) > 0.01)
    #expect(meanAbsoluteLuminanceDifference(normal, maximumSeed) > 0.01)
    #expect(abs(meanLuminance(normal) - meanLuminance(maximumSeed)) < 0.02)
}

@Test func rendererPreservesSourceExtent() throws {
    let renderer = try FilmRenderer()
    let source = CIImage(color: .init(red: 0.4, green: 0.25, blue: 0.15, alpha: 1))
        .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 64))
    let output = try renderer.render(source, recipe: .classic35)

    #expect(output.extent == source.extent)
}

@Test func filmToneExposureProtectsTheHighlightShoulder() throws {
    let renderer = try FilmRenderer()
    let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
    let recipe = FilmRecipe(
        id: "tone-test",
        name: "Tone Test",
        tone: .init(exposure: 1),
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )
    let middleSource = CIImage(color: .init(red: 0.18, green: 0.18, blue: 0.18, alpha: 1))
        .cropped(to: extent)
    let highlightSource = CIImage(color: .init(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        .cropped(to: extent)
    let extendedHighlightSource = CIImage(color: .init(red: 2, green: 2, blue: 2, alpha: 1))
        .cropped(to: extent)

    let middle = Double(renderFloatPixels(try renderer.render(middleSource, recipe: recipe), extent: extent)[0])
    let highlight = Double(renderFloatPixels(try renderer.render(highlightSource, recipe: recipe), extent: extent)[0])
    let extendedHighlight = Double(
        renderFloatPixels(try renderer.render(extendedHighlightSource, recipe: recipe), extent: extent)[0]
    )

    #expect(middle > 0.18)
    #expect(middle > 0.38)
    #expect(middle < 0.43)
    #expect(highlight > 0.9)
    #expect(highlight > 0.95)
    #expect(highlight < 1)
    #expect(extendedHighlight > highlight)
    #expect(extendedHighlight < 1)
    #expect(middle / 0.18 > highlight / 0.9)
}

@Test func positiveExposureCompressesColorAsItApproachesTheShoulder() throws {
    let renderer = try FilmRenderer()
    let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
    let recipe = FilmRecipe(
        id: "exposure-color-test",
        name: "Exposure Color Test",
        tone: .init(exposure: 1),
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )
    let middleSource = CIImage(color: .init(red: 0.30, green: 0.16, blue: 0.08, alpha: 1))
        .cropped(to: extent)
    let highlightSource = CIImage(color: .init(red: 0.92, green: 0.58, blue: 0.32, alpha: 1))
        .cropped(to: extent)

    let middleInput = renderFloatPixels(middleSource, extent: extent)
    let highlightInput = renderFloatPixels(highlightSource, extent: extent)
    let middleOutput = renderFloatPixels(
        try renderer.render(middleSource, recipe: recipe),
        extent: extent
    )
    let highlightOutput = renderFloatPixels(
        try renderer.render(highlightSource, recipe: recipe),
        extent: extent
    )

    let middleRetention = normalizedChroma(middleOutput) / normalizedChroma(middleInput)
    let highlightRetention = normalizedChroma(highlightOutput) / normalizedChroma(highlightInput)
    #expect(middleRetention < 1)
    #expect(highlightRetention < middleRetention)
}

@Test func filmToneSaturationAndWarmthRemainPhotographic() throws {
    let renderer = try FilmRenderer()
    let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
    let source = CIImage(color: .init(red: 0.52, green: 0.28, blue: 0.12, alpha: 1))
        .cropped(to: extent)
    var recipe = FilmRecipe(
        id: "color-tone-test",
        name: "Color Tone Test",
        tone: .init(saturation: -1),
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )

    let monochrome = renderFloatPixels(try renderer.render(source, recipe: recipe), extent: extent)
    #expect(abs(monochrome[0] - monochrome[1]) < 0.001)
    #expect(abs(monochrome[1] - monochrome[2]) < 0.001)

    recipe.tone = .init(warmth: 1)
    let neutralSource = CIImage(color: .init(red: 0.35, green: 0.35, blue: 0.35, alpha: 1))
        .cropped(to: extent)
    let warmed = renderFloatPixels(try renderer.render(neutralSource, recipe: recipe), extent: extent)
    #expect(warmed[0] > warmed[2])
    #expect(warmed[1] > warmed[2])
    let warmedLuminance = 0.2627002 * warmed[0] + 0.6779981 * warmed[1] + 0.0593017 * warmed[2]
    #expect(abs(warmedLuminance - 0.35) < 0.04)
}

@Test func filmToneVibranceProtectsSkinLikeHues() throws {
    let renderer = try FilmRenderer()
    let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
    let recipe = FilmRecipe(
        id: "vibrance-test",
        name: "Vibrance Test",
        tone: .init(vibrance: 1),
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )
    let skinColor = [Float(0.38), 0.28, 0.23]
    let foliageColor = [Float(0.25), 0.34, 0.22]
    let skinSource = CIImage(color: .init(
        red: CGFloat(skinColor[0]),
        green: CGFloat(skinColor[1]),
        blue: CGFloat(skinColor[2]),
        alpha: 1
    )).cropped(to: extent)
    let foliageSource = CIImage(color: .init(
        red: CGFloat(foliageColor[0]),
        green: CGFloat(foliageColor[1]),
        blue: CGFloat(foliageColor[2]),
        alpha: 1
    )).cropped(to: extent)

    let skin = renderFloatPixels(try renderer.render(skinSource, recipe: recipe), extent: extent)
    let foliage = renderFloatPixels(try renderer.render(foliageSource, recipe: recipe), extent: extent)
    let skinBoost = channelSpread(skin) / channelSpread(skinColor)
    let foliageBoost = channelSpread(foliage) / channelSpread(foliageColor)

    #expect(skinBoost < foliageBoost)
}

@Test func diffusionCreatesStrongControlledHighlightSpill() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 256)
    let black = CIImage(color: .init(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
    let practical = CIImage(color: .init(red: 1, green: 1, blue: 1, alpha: 1))
        .cropped(to: CGRect(x: 120, y: 120, width: 16, height: 16))
    let source = practical.composited(over: black)
    let recipe = FilmRecipe(
        id: "diffusion-test",
        name: "Diffusion Test",
        lightShaping: .init(isEnabled: false),
        diffusion: .init(amount: 0.25, bloom: 0.65, veil: 0.1, sourceBias: 0.2),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )

    let output = try FilmRenderer().render(source, recipe: recipe)
    let pixels = renderFloatPixels(output, extent: extent)
    let center = pixels[((128 * 256 + 128) * 4)]
    let nearHalo = pixels[((128 * 256 + 116) * 4)]
    let distantShadow = pixels[((32 * 256 + 32) * 4)]

    #expect(center < 0.85)
    #expect(nearHalo > 0.01)
    #expect(distantShadow < 0.005)
}

@Test func landscapeGlowIsAnExactIdentityAtZeroAmount() throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 64)
    let source = CIImage(color: .init(red: 0.48, green: 0.24, blue: 0.08, alpha: 1))
        .cropped(to: extent)
    let recipe = FilmRecipe(
        id: "glow-zero-test",
        name: "Glow Zero Test",
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        landscapeGlow: .init(isEnabled: true, amount: 0),
        grain: .init(isEnabled: false)
    )

    let input = renderFloatPixels(source, extent: extent)
    let output = renderFloatPixels(try FilmRenderer().render(source, recipe: recipe), extent: extent)
    #expect(meanAbsoluteLuminanceDifference(input, output) < 0.000_001)
}

@Test func landscapeGlowSpreadsBrightColorWithoutFoggingDeepShadows() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 256)
    let shadows = CIImage(color: .init(red: 0.025, green: 0.025, blue: 0.025, alpha: 1))
        .cropped(to: extent)
    let surroundingLandscape = CIImage(color: .init(red: 0.12, green: 0.12, blue: 0.12, alpha: 1))
        .cropped(to: CGRect(x: 72, y: 72, width: 112, height: 112))
    let warmLight = CIImage(color: .init(red: 1.0, green: 0.55, blue: 0.16, alpha: 1))
        .cropped(to: CGRect(x: 116, y: 116, width: 24, height: 24))
    let source = warmLight.composited(over: surroundingLandscape.composited(over: shadows))
    let recipe = FilmRecipe(
        id: "landscape-glow-test",
        name: "Landscape Glow Test",
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        landscapeGlow: .init(
            isEnabled: true,
            amount: 0.75,
            glowSize: 0.55,
            shadowProtection: 0.72,
            detail: 0.7
        ),
        grain: .init(isEnabled: false)
    )

    let pixels = renderFloatPixels(try FilmRenderer().render(source, recipe: recipe), extent: extent)
    let nearbyIndex = (128 * 256 + 108) * 4
    let distantIndex = (24 * 256 + 24) * 4
    let nearby = pixelLuminance(Array(pixels[nearbyIndex ..< nearbyIndex + 4]))
    let distant = pixelLuminance(Array(pixels[distantIndex ..< distantIndex + 4]))

    #expect(nearby > 0.12)
    #expect(distant < 0.03)
    #expect(pixels[nearbyIndex] > pixels[nearbyIndex + 2])
}

@Test func landscapeGlowAddsSubtleContrastInsteadOfMutingTheImage() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 128)
    let shadows = CIImage(color: .init(red: 0.10, green: 0.10, blue: 0.10, alpha: 1))
        .cropped(to: CGRect(x: 0, y: 0, width: 128, height: 128))
    let highlights = CIImage(color: .init(red: 0.55, green: 0.55, blue: 0.55, alpha: 1))
        .cropped(to: CGRect(x: 128, y: 0, width: 128, height: 128))
    let source = highlights.composited(over: shadows)
    let recipe = FilmRecipe(
        id: "glow-contrast-test",
        name: "Glow Contrast Test",
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        landscapeGlow: .init(
            isEnabled: true,
            amount: 0.5,
            glowSize: 0.5,
            shadowProtection: 0.72,
            detail: 0.7
        ),
        grain: .init(isEnabled: false)
    )

    let pixels = renderFloatPixels(try FilmRenderer().render(source, recipe: recipe), extent: extent)
    let darkIndex = (64 * 256 + 32) * 4
    let lightIndex = (64 * 256 + 224) * 4
    let dark = pixelLuminance(Array(pixels[darkIndex ..< darkIndex + 4]))
    let light = pixelLuminance(Array(pixels[lightIndex ..< lightIndex + 4]))

    #expect(dark < 0.10)
    #expect(light > 0.55)
    #expect(light - dark > 0.45)
}

@Test func landscapeGlowRetainsAnOverallOrtonBodyBelowTheHighlights() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 128)
    let coolMidtone = CIImage(color: .init(red: 0.12, green: 0.24, blue: 0.28, alpha: 1))
        .cropped(to: CGRect(x: 0, y: 0, width: 128, height: 128))
    let warmMidtone = CIImage(color: .init(red: 0.34, green: 0.22, blue: 0.10, alpha: 1))
        .cropped(to: CGRect(x: 128, y: 0, width: 128, height: 128))
    let source = warmMidtone.composited(over: coolMidtone)
    let recipe = FilmRecipe(
        id: "glow-overall-body-test",
        name: "Glow Overall Body Test",
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        landscapeGlow: .init(
            isEnabled: true,
            amount: 0.5,
            glowSize: 0.65,
            shadowProtection: 0.72,
            detail: 0.7
        ),
        grain: .init(isEnabled: false)
    )

    let input = renderFloatPixels(source, extent: extent)
    let output = renderFloatPixels(try FilmRenderer().render(source, recipe: recipe), extent: extent)
    #expect(meanAbsoluteLuminanceDifference(input, output) > 0.003)

    // The full-frame color layer should gently connect the two midtone regions,
    // even though neither side contains a conventional bright highlight.
    let coolEdgeIndex = (64 * 256 + 124) * 4
    #expect(output[coolEdgeIndex] > input[coolEdgeIndex])
}

@Test func landscapeGlowDetailControlRestoresFineLuminanceStructure() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 256)
    let dark = CIImage(color: .init(red: 0.22, green: 0.22, blue: 0.22, alpha: 1))
        .cropped(to: extent)
    let lightStripe = CIImage(color: .init(red: 0.58, green: 0.58, blue: 0.58, alpha: 1))
        .cropped(to: CGRect(x: 128, y: 0, width: 2, height: 256))
    let source = lightStripe.composited(over: dark)
    let renderer = try FilmRenderer()

    func edgeContrast(detail: Double) throws -> Float {
        let recipe = FilmRecipe(
            id: "glow-detail-\(detail)",
            name: "Glow Detail",
            lightShaping: .init(isEnabled: false),
            diffusion: .init(isEnabled: false),
            halation: .init(isEnabled: false),
            landscapeGlow: .init(
                isEnabled: true,
                amount: 1,
                glowSize: 0.5,
                shadowProtection: 0,
                detail: detail
            ),
            grain: .init(isEnabled: false)
        )
        let pixels = renderFloatPixels(try renderer.render(source, recipe: recipe), extent: extent)
        let stripe = pixels[(128 * 256 + 128) * 4]
        let neighbor = pixels[(128 * 256 + 126) * 4]
        return stripe - neighbor
    }

    let softened = try edgeContrast(detail: 0)
    let restored = try edgeContrast(detail: 1)
    #expect(restored > softened + 0.002)
}

@Test func landscapeGlowPreservesTransparencyWithoutDarkEdgeContamination() throws {
    let extent = CGRect(x: 0, y: 0, width: 128, height: 128)
    let clear = CIImage(color: .clear).cropped(to: extent)
    let opaqueSubject = CIImage(color: .init(red: 0.7, green: 0.35, blue: 0.12, alpha: 1))
        .cropped(to: CGRect(x: 32, y: 32, width: 64, height: 64))
    let source = opaqueSubject.composited(over: clear)
    let recipe = FilmRecipe(
        id: "glow-alpha-test",
        name: "Glow Alpha Test",
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        landscapeGlow: .init(isEnabled: true, amount: 1),
        grain: .init(isEnabled: false)
    )

    let input = renderFloatPixels(source, extent: extent)
    let output = renderFloatPixels(try FilmRenderer().render(source, recipe: recipe), extent: extent)
    for index in stride(from: 0, to: output.count, by: 4) {
        #expect(abs(input[index + 3] - output[index + 3]) < 0.000_001)
        if input[index + 3] == 0 {
            #expect(abs(output[index]) < 0.000_001)
            #expect(abs(output[index + 1]) < 0.000_001)
            #expect(abs(output[index + 2]) < 0.000_001)
        }
    }
}

@Test func lensBlurSoftensTheFieldEdgesWhileKeepingTheOpticalCenterSharp() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 256)
    let black = CIImage(color: .init(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
    let whiteHalf = CIImage(color: .init(red: 1, green: 1, blue: 1, alpha: 1))
        .cropped(to: CGRect(x: 128, y: 0, width: 128, height: 256))
    let source = whiteHalf.composited(over: black)
    let recipe = FilmRecipe(
        id: "lens-blur-test",
        name: "Lens Blur Test",
        lightShaping: .init(isEnabled: false),
        lensBlur: .init(
            isEnabled: true,
            amount: 1,
            falloff: 0.35,
            colorFringing: 0,
            focusX: 0,
            focusY: 0.5
        ),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )

    let pixels = renderFloatPixels(try FilmRenderer().render(source, recipe: recipe), extent: extent)
    let centerDarkSide = pixels[((128 * 256 + 5) * 4)]
    let edgeDarkSide = pixels[((128 * 256 + 123) * 4)]

    #expect(centerDarkSide < 0.02)
    #expect(edgeDarkSide > centerDarkSide + 0.02)
}

@Test func lensBlurRGBSeparationCreatesSoftPrismaticGhostsNearTheEdge() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 256)
    let black = CIImage(color: .init(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
    let whiteHalf = CIImage(color: .init(red: 1, green: 1, blue: 1, alpha: 1))
        .cropped(to: CGRect(x: 128, y: 0, width: 128, height: 256))
    let source = whiteHalf.composited(over: black)
    let recipe = FilmRecipe(
        id: "lens-fringe-test",
        name: "Lens Fringe Test",
        lightShaping: .init(isEnabled: false),
        lensBlur: .init(
            isEnabled: true,
            amount: 0.25,
            falloff: 0.2,
            colorFringing: 1,
            focusX: 0,
            focusY: 0.5
        ),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )

    let pixels = renderFloatPixels(try FilmRenderer().render(source, recipe: recipe), extent: extent)
    let edgeIndex = (128 * 256 + 126) * 4
    let channelSeparation = max(
        abs(pixels[edgeIndex] - pixels[edgeIndex + 1]),
        abs(pixels[edgeIndex + 2] - pixels[edgeIndex + 1])
    )

    #expect(channelSeparation > 0.02)
}

@Test func highStrengthLensBlurAndAberrationRemainContinuouslyFeathered() throws {
    let extent = CGRect(x: 0, y: 0, width: 384, height: 384)
    let black = CIImage(color: .init(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
    let whiteHalf = CIImage(color: .init(red: 1, green: 1, blue: 1, alpha: 1))
        .cropped(to: CGRect(x: 192, y: 0, width: 192, height: 384))
    let source = whiteHalf.composited(over: black)
    let recipe = FilmRecipe(
        id: "lens-smoothness-test",
        name: "Lens Smoothness Test",
        lightShaping: .init(isEnabled: false),
        lensBlur: .init(
            isEnabled: true,
            amount: 1,
            falloff: 0,
            colorFringing: 1,
            focusX: 0,
            focusY: 0.5
        ),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )

    let pixels = renderFloatPixels(try FilmRenderer().render(source, recipe: recipe), extent: extent)
    let transition = 150 ... 230

    // A sparse radial tap kernel produces a handful of repeated plateaus at high
    // strength. The native continuous blur should retain many tonal steps in every
    // separated channel through the same transition.
    for channel in 0 ..< 3 {
        let levels = Set(transition.map { x in
            let value = pixels[((192 * 384 + x) * 4) + channel]
            return Int((value * 200).rounded())
        })
        #expect(levels.count > 16)
    }
}

@Test func processingServiceWritesAReadableCollisionSafeOutput() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("GranularTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("frame.png")
    let sourceImage = CIImage(color: .init(red: 0.62, green: 0.28, blue: 0.12, alpha: 1))
        .cropped(to: CGRect(x: 0, y: 0, width: 80, height: 60))
    let context = CIContext()
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let sourceData = try #require(
        context.pngRepresentation(of: sourceImage, format: .RGBA8, colorSpace: colorSpace)
    )
    try sourceData.write(to: sourceURL)

    let service = try ImageProcessingService()
    let outputURL = try await service.process(
        sourceURL: sourceURL,
        destinationFolder: directory,
        recipe: .classic35,
        options: .init(format: .png)
    )

    #expect(outputURL.lastPathComponent == "frame — Granular.png")
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
    #expect(CIImage(contentsOf: outputURL)?.extent == sourceImage.extent)
}

@Test func watchedFolderRetriesFilesUntilProcessingSucceeds() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("GranularWatchTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("incoming.png")
    try Data([0x46, 0x49, 0x4C, 0x4D]).write(to: sourceURL)

    let recorder = WatchMonitorRecorder(succeedAfterAttempt: 2)
    let monitor = WatchedFolderMonitor(
        scanInterval: .milliseconds(15),
        retryDelay: .milliseconds(25)
    )
    await monitor.start(folder: directory) { urls in
        await recorder.handle(urls)
    } errorHandler: { message in
        await recorder.record(error: message)
    }

    let didRetry = await eventually {
        await recorder.attemptCount >= 2
    }
    await monitor.stop()

    #expect(didRetry)
    #expect(await recorder.attemptCount == 2)
    #expect(await recorder.errors.isEmpty)
}

@Test func watchedFolderReportsAnUnavailableIncomingFolder() async {
    let missingFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("MissingGranularWatchFolder-\(UUID().uuidString)", isDirectory: true)
    let recorder = WatchMonitorRecorder(succeedAfterAttempt: 1)
    let monitor = WatchedFolderMonitor(
        scanInterval: .milliseconds(15),
        retryDelay: .milliseconds(25)
    )
    await monitor.start(folder: missingFolder) { urls in
        await recorder.handle(urls)
    } errorHandler: { message in
        await recorder.record(error: message)
    }

    let reportedError = await eventually {
        await !recorder.errors.isEmpty
    }
    await monitor.stop()

    #expect(reportedError)
    #expect(await recorder.errors.first?.contains("no longer available") == true)
}

private actor WatchMonitorRecorder {
    private(set) var attemptCount = 0
    private(set) var errors: [String] = []
    private let succeedAfterAttempt: Int

    init(succeedAfterAttempt: Int) {
        self.succeedAfterAttempt = succeedAfterAttempt
    }

    func handle(_ urls: [URL]) -> Set<URL> {
        attemptCount += 1
        return attemptCount >= succeedAfterAttempt ? Set(urls) : []
    }

    func record(error: String) {
        errors.append(error)
    }
}

private func eventually(
    timeout: Duration = .seconds(1),
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

private func renderFloatPixels(_ image: CIImage, extent: CGRect) -> [Float] {
    let width = Int(extent.width)
    let height = Int(extent.height)
    var pixels = [Float](repeating: 0, count: width * height * 4)
    let context = CIContext(options: [.workingColorSpace: NSNull()])
    context.render(
        image,
        toBitmap: &pixels,
        rowBytes: width * 4 * MemoryLayout<Float>.size,
        bounds: extent,
        format: .RGBAf,
        colorSpace: nil
    )
    return pixels
}

private func opticalStrengthRecipe(
    diffusionAmount: Double = 0,
    halationAmount: Double = 0
) -> FilmRecipe {
    FilmRecipe(
        id: "optical-strength-test",
        name: "Optical Strength Test",
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: diffusionAmount > 0, amount: diffusionAmount, bloom: 0.65),
        halation: .init(isEnabled: halationAmount > 0, amount: halationAmount, spillRadius: 0.5),
        grain: .init(isEnabled: false)
    )
}

private func grainTestRecipe(chroma: Double) -> FilmRecipe {
    FilmRecipe(
        id: "grain-test-\(chroma)",
        name: "Grain Test",
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(
            amount: 0.5,
            grainSize: 10,
            chroma: chroma,
            shadowResponse: 0.72,
            highlightResponse: 0.28,
            seed: 1234
        )
    )
}

private struct LegacyFilmRecipe: Encodable {
    let id: String
    let name: String
    let tone: FilmToneSettings
    let lightShaping: LightShapingSettings
    let lensBlur: LensBlurSettings
    let diffusion: DiffusionSettings
    let halation: HalationSettings
    let grain: GrainSettings
}

private func channelSpread(_ pixels: [Float]) -> Float {
    guard pixels.count >= 3 else { return 0 }
    return max(pixels[0], max(pixels[1], pixels[2]))
        - min(pixels[0], min(pixels[1], pixels[2]))
}

private func colorDistance(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count >= 3, rhs.count >= 3 else { return 0 }
    let red = lhs[0] - rhs[0]
    let green = lhs[1] - rhs[1]
    let blue = lhs[2] - rhs[2]
    return sqrt(red * red + green * green + blue * blue)
}

private func normalizedChroma(_ pixels: [Float]) -> Float {
    guard pixels.count >= 3 else { return 0 }
    let luminance = max(
        0.000_001,
        0.2126 * pixels[0] + 0.7152 * pixels[1] + 0.0722 * pixels[2]
    )
    return channelSpread(pixels) / luminance
}

private func pixelLuminance(_ pixels: [Float]) -> Float {
    guard pixels.count >= 3 else { return 0 }
    return 0.2627002 * pixels[0] + 0.6779981 * pixels[1] + 0.0593017 * pixels[2]
}

private func meanChromaEnergy(_ pixels: [Float]) -> Double {
    var total = 0.0
    var count = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let red = Double(pixels[index])
        let green = Double(pixels[index + 1])
        let blue = Double(pixels[index + 2])
        let redGreen = red - green
        let blueGreen = blue - green
        total += redGreen * redGreen + blueGreen * blueGreen
        count += 1
    }
    return total / Double(max(1, count))
}

private func luminanceCoefficientOfVariation(_ pixels: [Float]) -> Double {
    var luminances: [Double] = []
    luminances.reserveCapacity(pixels.count / 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        luminances.append(
            0.2126 * Double(pixels[index])
                + 0.7152 * Double(pixels[index + 1])
                + 0.0722 * Double(pixels[index + 2])
        )
    }
    guard !luminances.isEmpty else { return 0 }
    let mean = luminances.reduce(0, +) / Double(luminances.count)
    guard mean > 0.000_001 else { return 0 }
    let variance = luminances.reduce(0) { partial, value in
        let difference = value - mean
        return partial + difference * difference
    } / Double(luminances.count)
    return sqrt(variance) / mean
}

private func meanLuminance(_ pixels: [Float]) -> Double {
    guard !pixels.isEmpty else { return 0 }
    var total = 0.0
    var count = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
        total += 0.2126 * Double(pixels[index])
            + 0.7152 * Double(pixels[index + 1])
            + 0.0722 * Double(pixels[index + 2])
        count += 1
    }
    return total / Double(max(1, count))
}

private func meanAbsoluteLuminanceDifference(_ lhs: [Float], _ rhs: [Float]) -> Double {
    let count = min(lhs.count, rhs.count)
    guard count >= 4 else { return 0 }
    var total = 0.0
    var pixels = 0
    for index in stride(from: 0, to: count, by: 4) {
        let lhsLuminance = 0.2126 * Double(lhs[index])
            + 0.7152 * Double(lhs[index + 1])
            + 0.0722 * Double(lhs[index + 2])
        let rhsLuminance = 0.2126 * Double(rhs[index])
            + 0.7152 * Double(rhs[index + 1])
            + 0.0722 * Double(rhs[index + 2])
        total += abs(lhsLuminance - rhsLuminance)
        pixels += 1
    }
    return total / Double(max(1, pixels))
}

private func renderStockPatches(
    _ renderer: FilmRenderer,
    stock: FilmStockID,
    amount: Double = 1,
    colors: [[Float]]
) throws -> [[Float]] {
    let extent = CGRect(x: 0, y: 0, width: colors.count, height: 1)
    var source = CIImage.empty()
    for (index, color) in colors.enumerated() {
        let patch = CIImage(color: .init(
            red: CGFloat(color[0]), green: CGFloat(color[1]), blue: CGFloat(color[2]), alpha: 1
        )).cropped(to: CGRect(x: index, y: 0, width: 1, height: 1))
        source = patch.composited(over: source)
    }
    let recipe = FilmRecipe(
        id: "stock-patches",
        name: "Stock Patches",
        tone: .init(stock: stock, stockAmount: amount),
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )
    let pixels = renderFloatPixels(try renderer.render(source, recipe: recipe), extent: extent)
    return colors.indices.map { Array(pixels[$0 * 4 ..< $0 * 4 + 3]) }
}

/// OKLab from linear Rec.2020, matching the renderer's film-tone kernel.
private func oklab(_ rgb: [Float]) -> [Float] {
    let x = 0.6369580 * rgb[0] + 0.1446169 * rgb[1] + 0.1688809 * rgb[2]
    let y = 0.2627002 * rgb[0] + 0.6779981 * rgb[1] + 0.0593017 * rgb[2]
    let z = 0.0280727 * rgb[1] + 1.0609851 * rgb[2]
    let l = cbrt(max(0.8190224 * x + 0.3619063 * y - 0.1288738 * z, 0))
    let m = cbrt(max(0.0329837 * x + 0.9292868 * y + 0.0361447 * z, 0))
    let s = cbrt(max(0.0481772 * x + 0.2642395 * y + 0.6335478 * z, 0))
    return [
        0.2104543 * l + 0.7936178 * m - 0.0040720 * s,
        1.9780000 * l - 2.4285922 * m + 0.4505937 * s,
        0.0259040 * l + 0.7827718 * m - 0.8086758 * s
    ]
}

private func labDistance(_ lhs: [Float], _ rhs: [Float]) -> Float {
    sqrt(zip(lhs, rhs).map { ($0 - $1) * ($0 - $1) }.reduce(0, +))
}
