import CoreImage
import Foundation
import ImageIO
import Testing
@testable import GranularCore

private let hdrSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
private let hdrContext = CIContext(options: [.workingColorSpace: hdrSpace, .workingFormat: CIFormat.RGBAh])

private func hdrPatch(_ rgb: [Float], width: Int = 32, height: Int = 32) -> CIImage {
    let pixels = Array(repeating: rgb + [1], count: width * height).flatMap { $0 }
    return pixels.withUnsafeBytes {
        CIImage(bitmapData: Data($0), bytesPerRow: width * 16,
                size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: hdrSpace)
    }
}

/// The SDR rendition of a synthetic HDR patch: each pixel scaled down to
/// reference white, as a hard-clipping camera would record it.
private func sdrPatch(_ rgb: [Float], width: Int = 32, height: Int = 32) -> CIImage {
    hdrPatch(rgb.map { $0 / max(1, rgb.max()!) }, width: width, height: height)
}

private func hdrPixels(_ image: CIImage) -> [Float] {
    let extent = image.extent.integral
    var pixels = [Float](repeating: 0, count: Int(extent.width * extent.height) * 4)
    hdrContext.render(image, toBitmap: &pixels, rowBytes: Int(extent.width) * 16,
                      bounds: extent, format: .RGBAf, colorSpace: hdrSpace)
    return pixels
}

private func hdrFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("GranularHDR-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func hdrFixture(at url: URL) throws {
    let base = hdrPatch([0.65, 0.55, 0.4], width: 128, height: 96).settingProperties([
        kCGImagePropertyGPSDictionary as String: [
            kCGImagePropertyGPSLatitude as String: 40.7,
            kCGImagePropertyGPSLatitudeRef as String: "N"
        ],
        kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifDateTimeOriginal as String: "2026:10:03 12:00:00"]
    ])
    let bright = hdrPatch([3.8, 3.2, 2.4], width: 64, height: 96)
        .transformed(by: .init(translationX: 64, y: 0))
    let hdr = bright.composited(over: base).settingContentHeadroom(4)
    try hdrContext.writeHEIFRepresentation(of: base, to: url, format: .RGBA8,
        colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
        options: [.hdrImage: hdr, .hdrGainMapAsRGB: true])
}

private func isoGainMap(at url: URL) throws -> CFDictionary? {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap)
}

@Test func hdrTonePreservesSDRCalibrationAndHighlightSeparation() throws {
    let renderer = try FilmRenderer()
    for stock in FilmStockID.allCases {
        for exposure in [-2.0, 0, 2] {
            let tone = FilmToneSettings(stock: stock, exposure: exposure, contrast: 0.2)
            for gray: Float in [0.02, 0.18, 0.6] {
                let source = hdrPatch([gray, gray * 0.7, gray * 0.4])
                let sdr = hdrPixels(try renderer.renderFilmTone(source, tone: tone))
                let hdr = hdrPixels(try renderer.renderFilmTone(source, tone: tone, hdr: source))
                #expect(zip(sdr, hdr).allSatisfy { abs($0 - $1) < 0.003 }, "\(stock), \(exposure)")
            }
            var previous: Float = 0
            for gray: Float in [1, 2, 4, 8] {
                let image = try renderer.renderFilmTone(
                    sdrPatch([gray, gray, gray]), tone: tone, hdr: hdrPatch([gray, gray, gray]))
                let pixels = hdrPixels(image)
                #expect(pixels.allSatisfy { $0.isFinite && $0 >= 0 }, "\(stock), \(exposure), \(gray)")
                #expect(pixels[0] > previous, "\(stock), \(exposure), \(gray)")
                previous = pixels[0]
            }
            #expect(previous > 1, "\(stock), \(exposure)")
        }
    }
}

@Test func hdrDisabledToneIsIdentityAndMonochromeStocksRemainNeutral() throws {
    let renderer = try FilmRenderer()
    let source = hdrPatch([4, 2, 0.5])
    let sdr = sdrPatch([4, 2, 0.5])
    let identity = try renderer.renderFilmTone(sdr, tone: .init(isEnabled: false), hdr: source)
    #expect(hdrPixels(source) == hdrPixels(identity))
    for stock in FilmStockID.allCases where stock.isMonochrome {
        let image = try renderer.renderFilmTone(sdr, tone: .init(stock: stock, stockAmount: 2), hdr: source)
        let pixel = hdrPixels(image)
        #expect(abs(pixel[0] - pixel[1]) < 0.005)
        #expect(abs(pixel[1] - pixel[2]) < 0.005)
    }
}

@Test func hdrOpticalRecipesAndPreviewRetainExtendedValues() throws {
    let renderer = try FilmRenderer()
    let exporter = ImageExporter()
    let source = hdrPatch([4, 3, 2], width: 128, height: 96).settingContentHeadroom(4)
    let sdr = sdrPatch([4, 3, 2], width: 128, height: 96)
    let materialized = try exporter.materialize(source)
    #expect(materialized.contentHeadroom == 4)
    for recipe in FilmRecipe.builtIns {
        let rendered = try renderer.render(sdr, hdr: materialized, recipe: recipe)
        #expect(hdrPixels(rendered).allSatisfy { $0.isFinite && $0 >= 0 })
        let preview = try exporter.previewImage(for: rendered, maximumDimension: 64, highDynamicRange: true)
        #expect(preview.bitsPerComponent == 16)
        #expect(preview.contentHeadroom > 1)
        #expect(preview.width == 64)
        #expect(hdrPixels(CIImage(cgImage: preview))[0] > 1)
    }
}

@Test func hdrHEICRoundTripHasFreshISOGainMapAndAnEditedSDRBase() async throws {
    let folder = try hdrFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sourceURL = folder.appendingPathComponent("original.heic")
    try hdrFixture(at: sourceURL)
    #expect(try isoGainMap(at: sourceURL) != nil)
    let renderer = try FilmRenderer()
    let sdrSource = try renderer.loadImage(at: sourceURL)
    let hdrSource = try renderer.loadImage(at: sourceURL, expandToHDR: true)
    #expect(hdrSource.contentHeadroom > 1)
    #expect(hdrPixels(sdrSource).max()! <= 1.01)
    let thumbnail = try ImageExporter().thumbnail(at: sourceURL, maximumDimension: 64, highDynamicRange: true)
    #expect(thumbnail.contentHeadroom > 1)
    #expect(hdrPixels(CIImage(cgImage: thumbnail)).max()! > 1.2)
    let sdrThumbnail = try ImageExporter().thumbnail(at: sourceURL, maximumDimension: 64)
    #expect(hdrPixels(CIImage(cgImage: sdrThumbnail)).max()! <= 1.01)

    var recipe = FilmRecipe.builtIns.first { $0.id == "raw" }!
    recipe.tone = .init(stock: .portra400, exposure: -0.5)
    let service = try ImageProcessingService()
    let output = try await service.process(sourceURL: sourceURL, destinationFolder: folder,
        recipe: recipe, options: .init(format: .heic, resizeLongEdge: 64, colorSpace: .displayP3))
    #expect(try isoGainMap(at: output) != nil)
    let hdr = try renderer.loadImage(at: output, expandToHDR: true)
    #expect(hdr.contentHeadroom > 1)
    #expect(hdr.extent.size == CGSize(width: 64, height: 48))
    #expect(hdrPixels(hdr).max()! > 1.2)
    let expectedHDR = hdrPixels(try renderer.render(sdrSource, hdr: hdrSource, recipe: recipe)
        .transformed(by: .init(scaleX: 0.5, y: 0.5)))
    let actualHDR = hdrPixels(hdr)
    let hdrError = zip(actualHDR, expectedHDR).reduce(Float(0)) { $0 + abs($1.0 - $1.1) } / Float(actualHDR.count)
    #expect(hdrError < 0.06)
    let actual = hdrPixels(try renderer.loadImage(at: output))
    let expectedImage = try renderer.render(sdrSource, recipe: recipe)
        .transformed(by: .init(scaleX: 0.5, y: 0.5))
    let expected = hdrPixels(expectedImage)
    let meanError = zip(actual, expected).reduce(Float(0)) { $0 + abs($1.0 - $1.1) } / Float(actual.count)
    #expect(meanError < 0.025)
    let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    #expect((properties[kCGImagePropertyOrientation] as? Int) == 1)
    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:10:03 12:00:00")
    #expect(exif?[kCGImagePropertyExifPixelXDimension] as? Int == 64)
    let preview = try await service.renderPreview(sourceURL: sourceURL, recipe: recipe, maximumDimension: 64,
                                                  highDynamicRange: true)
    #expect(preview.contentHeadroom > 1)
}

@Test func hdrOptOutAndOtherFormatsUseSDRFallback() async throws {
    let folder = try hdrFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sourceURL = folder.appendingPathComponent("original.heic")
    try hdrFixture(at: sourceURL)
    let service = try ImageProcessingService()
    let raw = FilmRecipe.builtIns.first { $0.id == "raw" }!
    for format in [OutputFormat.heic, .jpeg, .png, .tiff] {
        let options = OutputOptions(format: format, preserveHDR: format != .heic && format != .jpeg)
        #expect(!options.preservesHDR(for: sourceURL))
        let output = try await service.process(sourceURL: sourceURL, destinationFolder: folder,
            recipe: raw, options: options)
        #expect(try isoGainMap(at: output) == nil)
        let image = try FilmRenderer().loadImage(at: output, expandToHDR: true)
        #expect(image.contentHeadroom <= 1)
        #expect(hdrPixels(image).max()! <= 1.01)
    }
}

@Test func hdrSettingDefaultsOnForLegacyOptionsAndCanBeDisabled() throws {
    let old = Data(#"{"format":"heic","compressionQuality":0.9,"stripLocationMetadata":true}"#.utf8)
    #expect(try JSONDecoder().decode(OutputOptions.self, from: old).preserveHDR)
    let options = OutputOptions(preserveHDR: false)
    #expect(try JSONDecoder().decode(OutputOptions.self, from: JSONEncoder().encode(options)) == options)
}

@Test func hdrPQInputGetsAnSDRBaseAndAdaptiveHEICOutput() async throws {
    let folder = try hdrFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sourceURL = folder.appendingPathComponent("pq.heic")
    try hdrContext.writeHEIF10Representation(of: hdrPatch([4, 2, 0.5], width: 128, height: 96)
        .settingContentHeadroom(4), to: sourceURL,
        colorSpace: CGColorSpace(name: CGColorSpace.itur_2100_PQ)!, options: [:])
    let renderer = try FilmRenderer()
    #expect(try renderer.loadImage(at: sourceURL, expandToHDR: true).contentHeadroom > 1)
    let raw = FilmRecipe.builtIns.first { $0.id == "raw" }!
    let output = try await ImageProcessingService().process(sourceURL: sourceURL,
        destinationFolder: folder, recipe: raw, options: .init())
    // Decoded rather than inspected: in a parallel test run, ImageIO sometimes
    // reports no auxiliary data for this small file, though a fresh process
    // always finds the gain map in identical bytes.
    let decoded = try renderer.loadImage(at: output, expandToHDR: true)
    #expect(decoded.contentHeadroom > 1)
    #expect(hdrPixels(decoded).max()! > 1.2)
    let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
    let base = try #require(CGImageSourceCreateImageAtIndex(source, 0, [
        kCGImageSourceDecodeRequest: kCGImageSourceDecodeToSDR
    ] as CFDictionary))
    #expect(base.colorSpace?.isHDR() == false)
    #expect(hdrPixels(CIImage(cgImage: base)).max()! <= 1.01)
}

@Test func hdrLandscapeGlowKeepsColoredHighlightsAndLensRemainsFinite() throws {
    let renderer = try FilmRenderer()
    let source = hdrPatch([4, 2, 0.5], width: 128, height: 96)
    let sdr = sdrPatch([4, 2, 0.5], width: 128, height: 96)
    var recipe = FilmRecipe.builtIns.first { $0.id == "raw" }!
    recipe.landscapeGlow = .init(isEnabled: true, amount: 0.5)
    let output = hdrPixels(try renderer.render(sdr, hdr: source, recipe: recipe))
    #expect(output[0] > output[1] * 1.5)
    #expect(output[1] > output[2] * 2)
    recipe.lensBlur = .init(isEnabled: true, amount: 1)
    recipe.diffusion = .init(isEnabled: true, amount: 1)
    let bright = hdrPatch([8, 4, 1], width: 64, height: 96)
        .transformed(by: .init(translationX: 64, y: 0)).composited(over: source)
    let brightSDR = sdrPatch([8, 4, 1], width: 64, height: 96)
        .transformed(by: .init(translationX: 64, y: 0)).composited(over: sdr)
    let pixels = hdrPixels(try renderer.render(brightSDR, hdr: bright, recipe: recipe))
    #expect(pixels.allSatisfy { $0.isFinite && $0 >= 0 })
    #expect(pixels.max()! > 1)
}

@Test func hdrSparseHighlightsAreMeasuredEvenWithUnknownMetadata() throws {
    let source = hdrPatch([0.08, 0.08, 0.08], width: 256, height: 192)
    let bright = hdrPatch([8, 4, 2], width: 4, height: 4)
        .transformed(by: .init(translationX: 140, y: 80))
        .composited(over: source).settingContentHeadroom(0)
    let exporter = ImageExporter()
    let measured = try exporter.measuringHeadroom(bright)
    #expect(abs(measured.contentHeadroom - 8) < 0.02)
    // A headroom of 1 says nothing about the pixels, so it is measured too.
    #expect(abs(try exporter.resolvingHeadroom(bright.settingContentHeadroom(1)).contentHeadroom - 8) < 0.02)
    #expect(try exporter.resolvingHeadroom(bright.settingContentHeadroom(3)).contentHeadroom == 3)
    let preview = try exporter.previewImage(for: bright, maximumDimension: 256, highDynamicRange: true)
    #expect(preview.contentHeadroom > 7.9)
    let folder = try hdrFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let base = hdrPatch([0.7, 0.5, 0.25], width: 4, height: 4)
        .transformed(by: .init(translationX: 140, y: 80)).composited(over: source)
    let output = try exporter.export(image: base, hdrImage: bright,
        sourceURL: folder.appendingPathComponent("original.heic"), destinationFolder: folder,
        options: .init(format: .heic, colorSpace: .displayP3))
    #expect(try isoGainMap(at: output) != nil)
    let decoded = try FilmRenderer().loadImage(at: output, expandToHDR: true)
    #expect(decoded.contentHeadroom > 7.9)
    // The encoded gain map is lower resolution, so a four-pixel light loses
    // peak intensity through reconstruction. It must still decode above SDR.
    #expect(hdrPixels(decoded).max()! > 1)
}

@Test func hdrToneStaysSmoothThroughReferenceWhite() throws {
    // A ramp from 0.25 to 6 times reference white, with an SDR rendition that
    // rolls off smoothly to white (extended Reinhard), as a camera's would.
    let width = 384
    let values = (0..<width).map { 0.25 * pow(24, Float($0) / Float(width - 1)) }
    func ramp(_ transfer: (Float) -> Float) -> CIImage {
        let pixels = values.flatMap { value -> [Float] in let v = transfer(value); return [v, v, v, 1] }
        return pixels.withUnsafeBytes {
            CIImage(bitmapData: Data($0), bytesPerRow: width * 16,
                    size: CGSize(width: width, height: 1), format: .RGBAf, colorSpace: hdrSpace)
        }
    }
    let hdr = ramp { $0 }
    let sdr = ramp { $0 * (1 + $0 / 36) / (1 + $0) }
    let renderer = try FilmRenderer()
    for stock in [FilmStockID.none, .portra400] {
        for exposure in [-2.0, 0, 2] {
            let tone = FilmToneSettings(stock: stock, exposure: exposure)
            // The largest change in log-log slope between neighbors. A kink at
            // white shows as an abrupt jump. The SDR look has its own small
            // steps, from the stock cubes' interpolation; HDR must add none.
            func roughness(_ image: CIImage) -> (luminance: [Float], jump: Float) {
                let pixels = hdrPixels(image)
                let luminance = stride(from: 0, to: pixels.count, by: 4).map { pixels[$0 + 1] }
                let slopes = (1..<width).map {
                    log(luminance[$0] / luminance[$0 - 1]) / log(values[$0] / values[$0 - 1])
                }
                return (luminance, zip(slopes, slopes.dropFirst()).map { abs($0 - $1) }.max()!)
            }
            let look = roughness(try renderer.renderFilmTone(sdr, tone: tone))
            let (luminance, jump) = roughness(try renderer.renderFilmTone(sdr, tone: tone, hdr: hdr))
            #expect(luminance.allSatisfy { $0.isFinite && $0 > 0 }, "\(stock), \(exposure)")
            #expect(zip(luminance, luminance.dropFirst()).allSatisfy { $0 < $1 }, "\(stock), \(exposure)")
            #expect(jump < look.jump + 0.01, "\(stock), \(exposure): slope jump \(jump), SDR \(look.jump)")
            #expect(luminance.last! > 1.2, "\(stock), \(exposure)")
        }
    }
}

@Test func hdrSDRPreviewMatchesTheSDRExport() async throws {
    let folder = try hdrFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sourceURL = folder.appendingPathComponent("original.heic")
    try hdrFixture(at: sourceURL)
    var recipe = FilmRecipe.builtIns.first { $0.id == "raw" }!
    recipe.tone = .init(stock: .portra400, exposure: 0.5)
    let service = try ImageProcessingService()
    let preview = try await service.renderPreview(sourceURL: sourceURL, recipe: recipe, maximumDimension: 128)
    #expect(preview.contentHeadroom <= 1)
    #expect(preview.bitsPerComponent == 8)
    let output = try await service.process(sourceURL: sourceURL, destinationFolder: folder, recipe: recipe,
        options: .init(format: .png, colorSpace: .displayP3))
    let exported = hdrPixels(try FilmRenderer().loadImage(at: output))
    let previewed = hdrPixels(CIImage(cgImage: preview))
    #expect(exported.count == previewed.count)
    let error = zip(exported, previewed).reduce(Float(0)) { $0 + abs($1.0 - $1.1) } / Float(exported.count)
    #expect(error < 0.01)
    let stock = try await service.renderStockThumbnail(sourceURL: sourceURL, tone: recipe.tone,
                                                      stock: .portra400, maximumPixelSize: 64)
    #expect(stock.contentHeadroom <= 1)
    let hdrStock = try await service.renderStockThumbnail(sourceURL: sourceURL, tone: recipe.tone,
        stock: .portra400, maximumPixelSize: 64, highDynamicRange: true)
    #expect(hdrStock.contentHeadroom > 1)
}

@Test func hdrJPEGRoundTripHasAnISOGainMapAndMetadata() async throws {
    let folder = try hdrFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sourceURL = folder.appendingPathComponent("original.heic")
    try hdrFixture(at: sourceURL)
    var recipe = FilmRecipe.builtIns.first { $0.id == "raw" }!
    recipe.tone = .init(stock: .portra400)
    let output = try await ImageProcessingService().process(sourceURL: sourceURL, destinationFolder: folder,
        recipe: recipe, options: .init(format: .jpeg, colorSpace: .displayP3))
    #expect(["jpg", "jpeg"].contains(output.pathExtension))
    #expect(try isoGainMap(at: output) != nil)
    let renderer = try FilmRenderer()
    let hdr = try renderer.loadImage(at: output, expandToHDR: true)
    #expect(hdr.contentHeadroom > 1)
    #expect(hdrPixels(hdr).max()! > 1.2)
    #expect(hdrPixels(try renderer.loadImage(at: output)).max()! <= 1.01)
    let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:10:03 12:00:00")
}

@Test func hdrContentIsRecognizedFromMetadata() throws {
    let folder = try hdrFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let exporter = ImageExporter()
    let gainMap = folder.appendingPathComponent("gain.heic")
    try hdrFixture(at: gainMap)
    #expect(exporter.hasHDRContent(at: gainMap))
    let pq = folder.appendingPathComponent("pq.heic")
    try hdrContext.writeHEIF10Representation(of: hdrPatch([4, 2, 0.5]).settingContentHeadroom(4), to: pq,
        colorSpace: CGColorSpace(name: CGColorSpace.itur_2100_PQ)!, options: [:])
    #expect(exporter.hasHDRContent(at: pq))
    let sdr = folder.appendingPathComponent("sdr.jpg")
    try hdrContext.writeJPEGRepresentation(of: hdrPatch([0.6, 0.5, 0.4]), to: sdr,
        colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, options: [:])
    #expect(!exporter.hasHDRContent(at: sdr))
}

// Optional local review. User photographs and generated artifacts stay outside
// the repository. Set GRANULAR_HDR_REVIEW_INPUT and GRANULAR_HDR_REVIEW_OUTPUT.
@Test func hdrUserPhotoReview() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let input = environment["GRANULAR_HDR_REVIEW_INPUT"],
          let output = environment["GRANULAR_HDR_REVIEW_OUTPUT"] else { return }
    let folder = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: input),
        includingPropertiesForKeys: nil).filter { ["jpg", "jpeg", "heic", "heif"].contains($0.pathExtension.lowercased()) }
    let renderer = try FilmRenderer()
    let service = try ImageProcessingService()
    let exporter = ImageExporter()
    let raw = FilmRecipe.builtIns.first { $0.id == "raw" }!
    var portra = FilmRecipe.classic35
    portra.tone = .init(stock: .portra400)
    var recovered = portra
    recovered.tone.exposure = -1
    var report: [String] = []
    for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        let sdrSource = try renderer.loadImage(at: file)
        let hdr = try renderer.loadImage(at: file, expandToHDR: true)
        let hasISO = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil
        let hasApple = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
        let measured = try exporter.resolvingHeadroom(hdr)
        let name = file.deletingPathExtension().lastPathComponent
        report.append("\(name): \(Int(hdr.extent.width))×\(Int(hdr.extent.height)), headroom=\(measured.contentHeadroom), ISO gain map=\(hasISO), Apple gain map=\(hasApple)")
        for (label, recipe) in [("raw", raw), ("classic35", FilmRecipe.classic35), ("portra", portra), ("portra-minus1", recovered)] {
            let destination = folder.appendingPathComponent("\(name)-\(label).heic")
            let exported = try await service.process(sourceURL: file, destinationURL: destination, recipe: recipe,
                options: .init(format: .heic, resizeLongEdge: 1_920, colorSpace: .displayP3))
            let decoded = try renderer.loadImage(at: exported, expandToHDR: true)
            report.append("  \(label): output headroom=\(decoded.contentHeadroom), ISO gain map=\(try isoGainMap(at: exported) != nil)")
            if measured.contentHeadroom > 1 { #expect(try isoGainMap(at: exported) != nil) }
            else { #expect(try isoGainMap(at: exported) == nil) }
            let sdr = try renderer.loadImage(at: exported)
            try hdrContext.writePNGRepresentation(of: sdr,
                to: folder.appendingPathComponent("\(name)-\(label)-SDR.png"), format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [:])
            // Compare decoded HDR to the renderer at review size. Gain-map and
            // HEVC quantization may differ locally; a large error means the file
            // no longer describes the edited image even if a gain map exists.
            if measured.contentHeadroom > 1 {
                let rendered = try renderer.render(sdrSource, hdr: hdr, recipe: recipe)
                let expected = try exporter.previewImage(for: rendered, maximumDimension: 640, highDynamicRange: true)
                let actual = try exporter.previewImage(for: decoded, maximumDimension: 640, highDynamicRange: true)
                let a = hdrPixels(CIImage(cgImage: actual))
                let b = hdrPixels(CIImage(cgImage: expected))
                #expect(a.count == b.count)
                let error = zip(a, b).reduce(Float(0)) { $0 + abs($1.0 - $1.1) } / Float(a.count)
                report.append("    HDR mean pixel error=\(error)")
                #expect(error < 0.04)
            }
        }
        if environment["GRANULAR_HDR_REVIEW_FULL_SIZE"] == "1" {
            let destination = folder.appendingPathComponent("\(name)-portra-full.heic")
            let exported = try await service.process(sourceURL: file, destinationURL: destination,
                recipe: portra, options: .init(format: .heic, colorSpace: .displayP3))
            let decoded = try renderer.loadImage(at: exported, expandToHDR: true)
            #expect(decoded.extent.size == hdr.extent.size)
            #expect(try isoGainMap(at: exported) != nil)
            report.append("  full-size Portra: \(Int(decoded.extent.width))×\(Int(decoded.extent.height)), headroom=\(decoded.contentHeadroom)")
        }
    }
    let summary = report.joined(separator: "\n")
    print(summary)
    try summary.write(to: folder.appendingPathComponent("review.txt"), atomically: true, encoding: .utf8)
}
