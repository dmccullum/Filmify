import CoreGraphics
import CoreImage
import ImageIO
import Foundation

public actor ImageProcessingService {
    private let renderer: FilmRenderer
    private let exporter: ImageExporter

    public init() throws {
        renderer = try FilmRenderer()
        exporter = ImageExporter()
    }

    /// With `highDynamicRange`, an HDR photo previews as its HDR rendition;
    /// otherwise as the SDR rendition every export carries.
    public func renderPreview(
        sourceURL: URL,
        recipe: FilmRecipe,
        maximumDimension: CGFloat = 1_600,
        grainDimension: CGFloat? = nil,
        highDynamicRange: Bool = false
    ) throws -> CGImage {
        let source = try previewSource(
            for: sourceURL, maximumDimension: maximumDimension, highDynamicRange: highDynamicRange
        )
        let rendered = try renderer.render(
            source.sdr,
            hdr: source.hdr,
            recipe: recipe,
            previewMaximumDimension: maximumDimension,
            grainDimension: grainDimension,
            fullSize: source.fullSize
        )
        return try exporter.previewImage(
            for: rendered, maximumDimension: max(maximumDimension, grainDimension ?? 0),
            highDynamicRange: source.hdr != nil
        )
    }

    /// The open image decoded once at preview size. Every effect scales with
    /// the image's short edge, so rendering from it matches the full-size look.
    /// A couple of sizes are kept, so a quick preview while adjusting and a
    /// sharper one for a zoomed-in view don't decode the file in turn.
    private func previewSource(
        for url: URL, maximumDimension: CGFloat, highDynamicRange: Bool
    ) throws -> PreviewSource {
        if previewSourceURL != url {
            previewSourceURL = url
            previewSources = []
        }
        if let index = previewSources.firstIndex(where: {
            $0.maximumDimension == maximumDimension && $0.highDynamicRange == highDynamicRange
        }) {
            let cached = previewSources.remove(at: index)
            previewSources.append(cached)
            return cached
        }
        let sdr = try renderer.loadImage(at: url)
        let hdr = highDynamicRange ? try loadHDR(at: url, matching: sdr) : nil
        let scale = min(1, maximumDimension / max(sdr.extent.width, sdr.extent.height))
        func shrunk(_ image: CIImage) throws -> CIImage {
            try exporter.materialize(scale < 1
                ? image.samplingLinear().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                : image)
        }
        let source = PreviewSource(
            maximumDimension: maximumDimension,
            highDynamicRange: highDynamicRange,
            sdr: try shrunk(sdr),
            hdr: try hdr.map(shrunk),
            fullSize: sdr.extent.integral.size
        )
        previewSources.append(source)
        if previewSources.count > 2 {
            previewSources.removeFirst()
        }
        return source
    }

    /// The open image at one preview size. An HDR photo previewed in HDR keeps
    /// both renditions, since the HDR edit is made from the SDR one.
    private struct PreviewSource {
        let maximumDimension: CGFloat
        let highDynamicRange: Bool
        let sdr: CIImage
        let hdr: CIImage?
        let fullSize: CGSize
    }

    private var previewSourceURL: URL?
    /// Least recently used first.
    private var previewSources: [PreviewSource] = []

    /// The photo's HDR rendition, or nil when it has none to keep. SDR files
    /// are recognized from their metadata, without decoding them again.
    private func loadHDR(at url: URL, matching sdr: CIImage) throws -> CIImage? {
        guard exporter.hasHDRContent(at: url) else { return nil }
        let hdr = try exporter.resolvingHeadroom(renderer.loadImage(at: url, expandToHDR: true))
        guard hdr.contentHeadroom > 1, hdr.extent.integral == sdr.extent.integral else { return nil }
        return hdr
    }

    /// Renders a small Film Tone preview of one stock for the stock picker. With
    /// no source image, a generated color swatch stands in.
    public func renderStockThumbnail(
        sourceURL: URL?,
        tone: FilmToneSettings,
        stock: FilmStockID,
        maximumPixelSize: Int = 192,
        highDynamicRange: Bool = false
    ) throws -> CGImage {
        let source = try thumbnailSource(
            for: sourceURL, maximumPixelSize: maximumPixelSize, highDynamicRange: highDynamicRange
        )
        var settings = tone
        settings.isEnabled = true
        settings.stock = stock
        let rendered = try renderer.renderFilmTone(source.sdr, tone: settings, hdr: source.hdr)
        return try exporter.previewImage(for: rendered, maximumDimension: CGFloat(maximumPixelSize),
                                        highDynamicRange: source.hdr != nil)
    }

    private func thumbnailSource(
        for url: URL?, maximumPixelSize: Int, highDynamicRange: Bool
    ) throws -> (sdr: CIImage, hdr: CIImage?) {
        if let cached = thumbnailSourceCache,
           cached.url == url,
           cached.maximumPixelSize == maximumPixelSize,
           cached.highDynamicRange == highDynamicRange {
            return (cached.sdr, cached.hdr)
        }
        let sdr: CIImage
        var hdr: CIImage?
        if let url {
            let size = CGFloat(maximumPixelSize)
            sdr = CIImage(cgImage: try exporter.thumbnail(at: url, maximumDimension: size))
            if highDynamicRange, exporter.hasHDRContent(at: url) {
                let image = try exporter.resolvingHeadroom(CIImage(cgImage:
                    try exporter.thumbnail(at: url, maximumDimension: size, highDynamicRange: true)))
                if image.contentHeadroom > 1, image.extent == sdr.extent { hdr = image }
            }
        } else {
            sdr = Self.colorSwatch(width: maximumPixelSize, height: maximumPixelSize * 2 / 3)
        }
        thumbnailSourceCache = (url, maximumPixelSize, highDynamicRange, sdr, hdr)
        return (sdr, hdr)
    }

    private var thumbnailSourceCache: (
        url: URL?, maximumPixelSize: Int, highDynamicRange: Bool, sdr: CIImage, hdr: CIImage?
    )?

    /// Skin, foliage, sky and saturated primaries over a gray ramp: enough to
    /// show a stock's color and tone character without a photograph.
    private static func colorSwatch(width: Int, height: Int) -> CIImage {
        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.84, 0.62, 0.50), (0.45, 0.30, 0.22), (0.35, 0.47, 0.22), (0.38, 0.55, 0.78),
            (0.80, 0.18, 0.16), (0.90, 0.72, 0.20), (0.20, 0.55, 0.55), (0.45, 0.28, 0.55)
        ]
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let columns = colors.count / 2
        let patchWidth = CGFloat(width) / CGFloat(columns)
        let rampHeight = CGFloat(height) / 3
        let patchHeight = (CGFloat(height) - rampHeight) / 2
        var swatch = CIImage.empty()
        for (index, color) in colors.enumerated() {
            let column = CGFloat(index % columns)
            let row = CGFloat(index / columns)
            let patch = CIImage(color: CIColor(red: color.0, green: color.1, blue: color.2, colorSpace: sRGB)!)
                .cropped(to: CGRect(
                    x: column * patchWidth,
                    y: rampHeight + (1 - row) * patchHeight,
                    width: patchWidth,
                    height: patchHeight
                ))
            swatch = patch.composited(over: swatch)
        }
        let ramp = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: CGFloat(width), y: 0),
            "inputColor0": CIColor(red: 0.02, green: 0.02, blue: 0.02, colorSpace: sRGB)!,
            "inputColor1": CIColor(red: 0.96, green: 0.96, blue: 0.96, colorSpace: sRGB)!
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: CGFloat(width), height: rampHeight))
        return ramp.composited(over: swatch)
    }

    public func process(
        sourceURL: URL,
        destinationFolder: URL,
        recipe: FilmRecipe,
        options: OutputOptions
    ) throws -> URL {
        let source = try renderer.loadImage(at: sourceURL)
        let rendered = try renderer.render(source, recipe: recipe)
        let hdr = try renderHDR(source, sourceURL: sourceURL, recipe: recipe, options: options)
        return try exporter.export(
            image: rendered,
            hdrImage: hdr,
            sourceURL: sourceURL,
            destinationFolder: destinationFolder,
            recipeName: recipe.name,
            options: options
        )
    }

    public func process(
        sourceURL: URL,
        destinationURL: URL,
        recipe: FilmRecipe,
        options: OutputOptions
    ) throws -> URL {
        let source = try renderer.loadImage(at: sourceURL)
        let rendered = try renderer.render(source, recipe: recipe)
        let hdr = try renderHDR(source, sourceURL: sourceURL, recipe: recipe, options: options)
        return try exporter.export(
            image: rendered,
            hdrImage: hdr,
            sourceURL: sourceURL,
            destinationFolder: destinationURL.deletingLastPathComponent(),
            destinationURL: destinationURL,
            options: options
        )
    }

    /// The edit's HDR rendition, when the photo has one and the output keeps it.
    private func renderHDR(
        _ source: CIImage, sourceURL: URL, recipe: FilmRecipe, options: OutputOptions
    ) throws -> CIImage? {
        guard options.preservesHDR(for: sourceURL),
              let hdr = try loadHDR(at: sourceURL, matching: source) else { return nil }
        return try renderer.render(source, hdr: hdr, recipe: recipe)
    }
}
