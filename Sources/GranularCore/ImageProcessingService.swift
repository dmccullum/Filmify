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

    public func renderPreview(
        sourceURL: URL,
        recipe: FilmRecipe,
        maximumDimension: CGFloat = 1_600,
        grainDimension: CGFloat? = nil
    ) throws -> CGImage {
        let source = try previewSource(for: sourceURL, maximumDimension: maximumDimension)
        let rendered = try renderer.render(
            source,
            recipe: recipe,
            previewMaximumDimension: maximumDimension,
            grainDimension: grainDimension
        )
        return try exporter.previewImage(
            for: rendered, maximumDimension: max(maximumDimension, grainDimension ?? 0)
        )
    }

    /// The open image decoded once at preview size. Every effect scales with
    /// the image's short edge, so rendering from it matches the full-size look.
    /// A couple of sizes are kept, so a quick preview while adjusting and a
    /// sharper one for a zoomed-in view don't decode the file in turn.
    private func previewSource(for url: URL, maximumDimension: CGFloat) throws -> CIImage {
        if previewSourceURL != url {
            previewSourceURL = url
            previewSources = []
        }
        if let index = previewSources.firstIndex(where: { $0.maximumDimension == maximumDimension }) {
            let cached = previewSources.remove(at: index)
            previewSources.append(cached)
            return cached.image
        }
        let source = try renderer.loadImage(at: url)
        let scale = min(1, maximumDimension / max(source.extent.width, source.extent.height))
        let scaled = scale < 1
            ? source.samplingLinear()
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : source
        let image = try exporter.materialize(scaled)
        previewSources.append((maximumDimension, image))
        if previewSources.count > 2 {
            previewSources.removeFirst()
        }
        return image
    }

    private var previewSourceURL: URL?
    /// Least recently used first.
    private var previewSources: [(maximumDimension: CGFloat, image: CIImage)] = []

    /// Renders a small Film Tone preview of one stock for the stock picker. With
    /// no source image, a generated color swatch stands in.
    public func renderStockThumbnail(
        sourceURL: URL?,
        tone: FilmToneSettings,
        stock: FilmStockID,
        maximumPixelSize: Int = 192
    ) throws -> CGImage {
        let source = try thumbnailSource(for: sourceURL, maximumPixelSize: maximumPixelSize)
        var settings = tone
        settings.isEnabled = true
        settings.stock = stock
        let rendered = try renderer.renderFilmTone(source, tone: settings)
        return try exporter.previewImage(for: rendered, maximumDimension: CGFloat(maximumPixelSize))
    }

    private func thumbnailSource(for url: URL?, maximumPixelSize: Int) throws -> CIImage {
        if let cached = thumbnailSourceCache,
           cached.url == url,
           cached.maximumPixelSize == maximumPixelSize {
            return cached.image
        }
        let image: CIImage
        if let url {
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
                  ] as CFDictionary) else {
                throw FilmRendererError.imageLoadFailed(url)
            }
            image = CIImage(cgImage: thumbnail)
        } else {
            image = Self.colorSwatch(width: maximumPixelSize, height: maximumPixelSize * 2 / 3)
        }
        thumbnailSourceCache = (url, maximumPixelSize, image)
        return image
    }

    private var thumbnailSourceCache: (url: URL?, maximumPixelSize: Int, image: CIImage)?

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
        return try exporter.export(
            image: rendered,
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
        return try exporter.export(
            image: rendered,
            sourceURL: sourceURL,
            destinationFolder: destinationURL.deletingLastPathComponent(),
            destinationURL: destinationURL,
            options: options
        )
    }
}
