import CoreImage
import Foundation
import Testing
@testable import GranularCore

private let halationColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!

private func halationRecipe(_ settings: HalationSettings = .init()) -> FilmRecipe {
    FilmRecipe(
        id: "halation-test", name: "Halation Test", tone: .init(isEnabled: false),
        lightShaping: .init(isEnabled: false), diffusion: .init(isEnabled: false),
        halation: settings, grain: .init(isEnabled: false)
    )
}

private func halationFixture(size: Int = 256, pixel: (Int, Int) -> [Float]) -> CIImage {
    var pixels = [Float]()
    pixels.reserveCapacity(size * size * 4)
    for y in 0 ..< size {
        for x in 0 ..< size { pixels.append(contentsOf: pixel(x, y)) }
    }
    return pixels.withUnsafeBytes {
        CIImage(bitmapData: Data($0), bytesPerRow: size * 16,
                size: CGSize(width: size, height: size), format: .RGBAf,
                colorSpace: halationColorSpace)
    }
}

private func halationPixels(_ image: CIImage, workingFormat: CIFormat = .RGBAf) -> [Float] {
    let extent = image.extent.integral
    var pixels = [Float](repeating: 0, count: Int(extent.width * extent.height) * 4)
    let context = CIContext(options: [
        .workingColorSpace: halationColorSpace, .workingFormat: workingFormat
    ])
    context.render(image, toBitmap: &pixels, rowBytes: Int(extent.width) * 16,
                   bounds: extent, format: .RGBAf, colorSpace: halationColorSpace)
    return pixels
}

@Test func halationPreservesUniformFieldsIncludingHDR() throws {
    let renderer = try FilmRenderer()
    for color: [Float] in [[0, 0, 0, 1], [0.18, 0.18, 0.18, 1], [1, 1, 1, 1],
                           [4, 2, 0.5, 1], [0.12, 0.04, 0.02, 0.25]] {
        let source = halationFixture(size: 64) { _, _ in color }
        for amount in [0.0, 0.15, 0.5, 1.0] {
            let output = halationPixels(try renderer.render(source, recipe: halationRecipe(.init(amount: amount))))
            #expect(zip(output, halationPixels(source)).allSatisfy { abs($0 - $1) < 0.0001 })
        }
    }
}

@Test func halationConservesOpaqueChannelEnergyAndHasAWiderRedTail() throws {
    let renderer = try FilmRenderer()
    let source = halationFixture { x, y in
        let light: Float = (126 ..< 130).contains(x) && (126 ..< 130).contains(y) ? 4 : 0
        return [light, light, light, 1]
    }
    let input = halationPixels(source)
    for amount in [0.15, 0.5, 1.0] {
        let pixels = halationPixels(try renderer.render(source, recipe: halationRecipe(
            .init(amount: amount, spillRadius: 1, tail: 0.65, greenLeakage: 0.5)
        )))
        var total = [Double](repeating: 0, count: 3)
        var moment = total
        var haloEnergy = total
        for y in 0 ..< 256 {
            for x in 0 ..< 256 {
                let index = (y * 256 + x) * 4
                let distanceSquared = pow(Double(x) - 127.5, 2) + pow(Double(y) - 127.5, 2)
                for c in 0 ..< 3 {
                    total[c] += Double(pixels[index + c])
                    if !(126 ..< 130).contains(x) || !(126 ..< 130).contains(y) {
                        moment[c] += Double(pixels[index + c]) * distanceSquared
                        haloEnergy[c] += Double(pixels[index + c])
                    }
                }
            }
        }
        #expect(pixels.allSatisfy { $0 >= -0.00001 && $0.isFinite })
        #expect(stride(from: 2, to: pixels.count, by: 4).allSatisfy { abs(pixels[$0] - input[$0]) < 0.00001 })
        for energy in total { #expect(abs(energy - 64) / 64 < 0.002) }
        // Compare the spatial distribution of halo light independently of its
        // total intensity, so a weaker green halo alone cannot pass this test.
        let redVariance = moment[0] / haloEnergy[0]
        let greenVariance = moment[1] / haloEnergy[1]
        #expect(redVariance > greenVariance * 2)
    }
}

@Test func halationDoesNotColorOrLeakThroughTransparency() throws {
    let renderer = try FilmRenderer()
    let source = halationFixture { x, _ in
        let alpha: Float = x < 96 ? 0 : (x < 160 ? 0.3 : 1)
        return [0.8 * alpha, 0.4 * alpha, 0.2 * alpha, alpha]
    }
    let output = halationPixels(try renderer.render(source, recipe: halationRecipe(
        .init(amount: 1, spillRadius: 1, tail: 1)
    )))
    let input = halationPixels(source)
    let maximumError = zip(output, input).map { abs($0 - $1) }.max()!
    // Allow 0.001 absolute RGB error from Core Image's blur/intermediate
    // precision, while checking alpha and empty coverage separately below.
    #expect(maximumError < 0.001)
    #expect(stride(from: 3, to: output.count, by: 4).allSatisfy { output[$0] == input[$0] })
    #expect(stride(from: 0, to: output.count, by: 4).allSatisfy {
        input[$0 + 3] != 0 || (output[$0] == 0 && output[$0 + 1] == 0 && output[$0 + 2] == 0)
    })
}

@Test func halationIsLinearInExposureWithoutAHighlightThreshold() throws {
    let renderer = try FilmRenderer()
    let settings = halationRecipe(.init(amount: 0.4, spillRadius: 1))
    let dim = halationFixture { x, _ in x < 128 ? [0, 0, 0, 1] : [0.125, 0.0625, 0.025, 1] }
    let bright = halationFixture { x, _ in x < 128 ? [0, 0, 0, 1] : [4, 2, 0.8, 1] }
    let dimPixels = halationPixels(try renderer.render(dim, recipe: settings))
    let brightPixels = halationPixels(try renderer.render(bright, recipe: settings))
    #expect(dimPixels[(128 * 256 + 126) * 4] > 0)
    #expect(dimPixels.indices.filter { $0 % 4 != 3 }.allSatisfy {
        abs(dimPixels[$0] * 32 - brightPixels[$0]) < 0.0002
    })
}

@Test func halationSmallPreviewMatchesDownsampledFullResolution() throws {
    let renderer = try FilmRenderer()
    let settings = halationRecipe(.init(amount: 0.4, spillRadius: 0, tail: 0.7))
    let source = halationFixture(size: 1024) { x, _ in x < 512 ? [0, 0, 0, 1] : [1, 1, 1, 1] }
    let preview = source.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
    let small = halationPixels(try renderer.render(preview, recipe: settings))
    let full = halationPixels(try renderer.render(source, recipe: settings)
        .transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25)))
    // Compare the total spill outside a two-pixel sampling band at the edge.
    let sampleIndices = (112 ..< 126).map { (128 * 256 + $0) * 4 }
    let smallSpill = sampleIndices.reduce(Float(0)) { $0 + small[$1] }
    let fullSpill = sampleIndices.reduce(Float(0)) { $0 + full[$1] }
    #expect(abs(smallSpill - fullSpill) < 0.006)
}

@Test func halationClampsImportedSpatialAndColorControls() throws {
    let source = halationFixture { x, _ in x < 128 ? [0, 0, 0, 1] : [1, 1, 1, 1] }
    let renderer = try FilmRenderer()
    let invalid = HalationSettings(amount: 0.4, spillRadius: -1, tail: 2,
                                    colorShift: 2, saturation: -1, greenLeakage: 1)
    let clamped = HalationSettings(amount: 0.4, spillRadius: 0, tail: 1,
                                    colorShift: 1, saturation: 0, greenLeakage: 0.5)
    let actual = halationPixels(try renderer.render(source, recipe: halationRecipe(invalid)))
    let expected = halationPixels(try renderer.render(source, recipe: halationRecipe(clamped)))
    #expect(zip(actual, expected).allSatisfy { abs($0 - $1) < 0.0001 })
}

@Test func halationEdgeIsMonotonicAndDoesNotTintUniformHighlightCores() throws {
    let source = halationFixture { x, _ in x < 128 ? [0, 0, 0, 1] : [1, 1, 1, 1] }
    let renderer = try FilmRenderer()
    let image = try renderer.render(source, recipe: halationRecipe(
        .init(amount: 0.4, spillRadius: 1, tail: 1, greenLeakage: 0.5)
    ))
    let pixels = halationPixels(image)
    let row = 128 * 256 * 4
    for channel in 0 ..< 3 {
        #expect((0 ..< 255).allSatisfy {
            pixels[row + $0 * 4 + channel] <= pixels[row + ($0 + 1) * 4 + channel] + 0.0001
        })
        #expect(abs(pixels[row + 240 * 4 + channel] - 1) < 0.0001)
    }
    #expect(pixels[row + 125 * 4] > pixels[row + 125 * 4 + 1])
    #expect(pixels[row + 127 * 4 + 1] > 0)
    // Exercise the same half-float working format as ImageExporter as well.
    let production = halationPixels(image, workingFormat: .RGBAh)
    #expect(zip(production, pixels).allSatisfy { abs($0 - $1) < 0.002 })
}

@Test func halationRespectsSourceColorAndTranslatedExtents() throws {
    let source = halationFixture { x, _ in x < 128 ? [0, 0, 0, 1] : [0, 0, 4, 1] }
    let renderer = try FilmRenderer()
    let recipe = halationRecipe(.init(amount: 1, spillRadius: 1, tail: 1))
    // Blue-only exposure cannot manufacture red or green photons in this model.
    let output = halationPixels(try renderer.render(source, recipe: recipe))
    #expect(zip(output, halationPixels(source)).allSatisfy { abs($0 - $1) < 0.0001 })

    let edge = halationFixture { x, _ in x < 128 ? [0, 0, 0, 1] : [1, 1, 1, 1] }
    let shifted = edge.transformed(by: CGAffineTransform(translationX: -51, y: 83))
    let shiftedOutput = try renderer.render(shifted, recipe: recipe)
    #expect(shiftedOutput.extent == shifted.extent)
    let original = halationPixels(try renderer.render(edge, recipe: recipe))
    #expect(zip(halationPixels(shiftedOutput), original).allSatisfy { abs($0 - $1) < 0.0001 })
}

// Optional review artifacts from the actual Core Image renderer, in display sRGB.
// HALATION_REVIEW_DIRECTORY=/tmp/halation swift test --filter halationReviewFixtures
@Test func halationReviewFixtures() throws {
    guard let path = ProcessInfo.processInfo.environment["HALATION_REVIEW_DIRECTORY"] else { return }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = halationFixture(size: 768) { x, y in
        let background: Float = y < 384 ? 0 : 0.04
        if y > 512 { return x < 384 ? [background, background, background, 1] : [1, 1, 1, 1] }
        for (index, center) in [128, 384, 640].enumerated() {
            let radius = y < 256 ? 5 : 30
            let centerY = y < 256 ? 128 : 384
            if (x - center) * (x - center) + (y - centerY) * (y - centerY) < radius * radius {
                return index == 0 ? [1, 1, 1, 1] : (index == 1 ? [8, 8, 8, 1] : [4, 0.5, 0.05, 1])
            }
        }
        return [background, background, background, 1]
    }
    let renderer = try FilmRenderer()
    let context = CIContext(options: [.workingColorSpace: halationColorSpace, .workingFormat: CIFormat.RGBAf])
    for (name, amount) in [("off", 0.0), ("classic", 0.15), ("strong", 0.5), ("maximum", 1.0)] {
        let image = try renderer.render(source, recipe: halationRecipe(.init(amount: amount, spillRadius: 0.7)))
        let data = try #require(context.pngRepresentation(of: image, format: .RGBA8,
                                  colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    for name in ["one", "two", "three"] {
        let url = root.appendingPathComponent("Website/public/result-\(name)-before.jpeg")
        let photo = try renderer.loadImage(at: url)
        for (label, amount) in [("off", 0.0), ("classic", 0.15), ("strong", 0.5)] {
            let image = try renderer.render(photo, recipe: halationRecipe(.init(amount: amount)))
            let data = try #require(context.pngRepresentation(of: image, format: .RGBA8,
                                      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
            try data.write(to: directory.appendingPathComponent("photo-\(name)-\(label).png"))
        }
    }
}
