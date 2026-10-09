import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageExporterError: LocalizedError {
    case unsupportedSourceFormat
    case destinationCreationFailed
    case imageCreationFailed
    case finalizeFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedSourceFormat:
            "This image format is not supported yet."
        case .destinationCreationFailed:
            "Granular could not create the output file."
        case .imageCreationFailed:
            "Granular could not create the rendered image."
        case .finalizeFailed:
            "Granular could not finish writing the output file."
        }
    }
}

public final class ImageExporter: @unchecked Sendable {
    private let context: CIContext

    public init() {
        let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
        context = CIContext(options: [
            .workingColorSpace: workingColorSpace,
            .workingFormat: CIFormat.RGBAh,
            .cacheIntermediates: false
        ])
    }

    /// Whether the file holds an HDR rendition: a gain map, an HDR transfer
    /// function, or extended-range pixels. Reads metadata only.
    func hasHDRContent(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        for type in [kCGImageAuxiliaryDataTypeISOGainMap, kCGImageAuxiliaryDataTypeHDRGainMap]
        where CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) != nil {
            return true
        }
        // Creating the image doesn't decode its pixels.
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        if image.bitmapInfo.contains(.floatComponents) { return true }
        guard let colorSpace = image.colorSpace else { return false }
        return colorSpace.isHDR() || CGColorSpaceUsesExtendedRange(colorSpace)
    }

    /// Keeps a headroom the decoder knows, and measures one it doesn't. A
    /// headroom of 1 is no evidence the pixels stay below reference white.
    func resolvingHeadroom(_ image: CIImage) throws -> CIImage {
        if image.contentHeadroom > 1 { return image }
        return try measuringHeadroom(image)
    }

    /// Measure the actual extended pixels. System HDR statistics can report 1
    /// for photographs with sparse highlights even when their pixels exceed 1;
    /// that causes the HEIF encoder to omit the gain map. A GPU maximum reduction
    /// keeps those highlights and avoids copying a full float bitmap to the CPU.
    func measuringHeadroom(_ image: CIImage) throws -> CIImage {
        guard !image.extent.isEmpty, !image.extent.isInfinite,
              let maximum = CIFilter(name: "CIAreaMaximum", parameters: [
                kCIInputImageKey: image,
                kCIInputExtentKey: CIVector(cgRect: image.extent)
              ])?.outputImage else { throw ImageExporterError.imageCreationFailed }
        var pixel = [Float](repeating: 0, count: 4)
        context.render(maximum, toBitmap: &pixel, rowBytes: 16,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf,
                       colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!)
        guard pixel.prefix(3).allSatisfy(\.isFinite) else { throw ImageExporterError.imageCreationFailed }
        return image.settingContentHeadroom(max(1, pixel[0], pixel[1], pixel[2]))
    }

    /// A downsized image of the file. With `highDynamicRange`, an HDR photo
    /// comes as its HDR rendition, in half floats; otherwise as its SDR one.
    public func thumbnail(
        at url: URL, maximumDimension: CGFloat = 1_600, highDynamicRange: Bool = false
    ) throws -> CGImage {
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maximumDimension))
        ]
        if highDynamicRange {
            options[kCGImageSourceShouldAllowFloat] = true
            options[kCGImageSourceDecodeRequest] = kCGImageSourceDecodeToHDR
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FilmRendererError.imageLoadFailed(url)
        }
        // ImageIO retains the source's image-specific tone mapping information.
        return image
    }

    /// Renders an image once into a half-float bitmap, so later renders start
    /// from decoded pixels instead of decoding the file again.
    public func materialize(_ image: CIImage) throws -> CIImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
        guard let cgImage = context.createCGImage(
            image,
            from: image.extent.integral,
            format: .RGBAh,
            colorSpace: colorSpace,
            deferred: false
        ) else {
            throw ImageExporterError.imageCreationFailed
        }
        return CIImage(cgImage: cgImage).settingContentHeadroom(image.contentHeadroom)
    }

    /// Renders straight to a bitmap for display; encoding a preview to a file
    /// format and decoding it again costs several times the render itself.
    /// It renders here and now: left to itself, Core Image defers large
    /// images until they're first drawn, which would be on the main thread.
    public func previewImage(
        for image: CIImage, maximumDimension: CGFloat = 1_600, highDynamicRange: Bool = false
    ) throws -> CGImage {
        let scale = min(1, maximumDimension / max(image.extent.width, image.extent.height))
        let preview = scale < 1
            ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : image
        let colorSpace = CGColorSpace(name: highDynamicRange
            ? CGColorSpace.extendedLinearDisplayP3 : CGColorSpace.displayP3)!
        guard let cgImage = context.createCGImage(
            preview,
            from: preview.extent.integral,
            format: highDynamicRange ? .RGBAh : .RGBA8,
            colorSpace: colorSpace,
            deferred: false
        ) else {
            throw ImageExporterError.imageCreationFailed
        }
        // Custom kernels invalidate the source's brightness statistics. Measure
        // the finished pixels so UIKit/SwiftUI can adapt them to display headroom.
        if highDynamicRange {
            let measured = try measuringHeadroom(CIImage(cgImage: cgImage))
            guard let tagged = CGImageCreateCopyWithContentHeadroom(measured.contentHeadroom, cgImage) else {
                throw ImageExporterError.imageCreationFailed
            }
            return tagged
        }
        return cgImage
    }

    public func export(
        image: CIImage,
        hdrImage: CIImage? = nil,
        sourceURL: URL,
        destinationFolder: URL,
        destinationURL: URL? = nil,
        recipeName: String = "",
        options: OutputOptions
    ) throws -> URL {
        let format = options.resolvedFormat(for: sourceURL)
        let type = try uniformType(for: format)
        let outputURL = destinationURL ?? OutputNaming.uniqueURL(
            template: options.filenameTemplate,
            name: sourceURL.deletingPathExtension().lastPathComponent,
            recipe: recipeName,
            folder: destinationFolder,
            fileExtension: type.preferredFilenameExtension ?? "tiff"
        )
        let actualDestinationFolder = outputURL.deletingLastPathComponent()
        let temporaryURL = actualDestinationFolder
            .appendingPathComponent(".granular-\(UUID().uuidString)")
            .appendingPathExtension(type.preferredFilenameExtension ?? "tmp")

        let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil)
        let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) } as? [CFString: Any]
        let convertsColorSpace = options.colorSpace != .keepSource
        let outputColorSpace = options.colorSpace.cgColorSpace
            ?? sourceColorSpace(from: source)
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let sized = resized(image, for: options)

        guard let cgImage = context.createCGImage(
            sized,
            from: sized.extent,
            format: .RGBA8,
            colorSpace: outputColorSpace
        ) else {
            throw ImageExporterError.imageCreationFailed
        }

        var outputProperties = properties ?? [:]
        // Camera-specific HDR hints describe the original, not the edited pair.
        outputProperties.removeValue(forKey: kCGImagePropertyMakerAppleDictionary)
        outputProperties[kCGImagePropertyOrientation] = 1
        outputProperties[kCGImagePropertyPixelWidth] = cgImage.width
        outputProperties[kCGImagePropertyPixelHeight] = cgImage.height
        var exif = outputProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        exif[kCGImagePropertyExifPixelXDimension] = cgImage.width
        exif[kCGImagePropertyExifPixelYDimension] = cgImage.height
        var tiff = outputProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        tiff[kCGImagePropertyTIFFOrientation] = 1
        outputProperties[kCGImagePropertyTIFFDictionary] = tiff
        if options.stripLocationMetadata {
            outputProperties.removeValue(forKey: kCGImagePropertyGPSDictionary)
        }
        if convertsColorSpace {
            // The source’s profile name and EXIF color tag describe pixels
            // that are no longer in that color space.
            outputProperties.removeValue(forKey: kCGImagePropertyProfileName)
            exif[kCGImagePropertyExifColorSpace] = options.colorSpace == .sRGB ? 1 : 65_535
        }
        outputProperties[kCGImagePropertyExifDictionary] = exif
        if format == .jpeg || format == .heic {
            outputProperties[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, options.compressionQuality))
        }

        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        if options.preservesHDR(for: sourceURL), let hdrImage {
            let hdr = resized(hdrImage, for: options)
            guard hdr.extent == sized.extent else { throw ImageExporterError.imageCreationFailed }
            // Render the HDR image once: measuring its peak and encoding it would
            // each render every effect again.
            let measuredHDR = try measuringHeadroom(materialize(hdr))
            // The SDR base is deliberately supplied, rather than derived from
            // the edited HDR image. Core Image generates a fresh ISO gain map.
            let base = CIImage(cgImage: cgImage).settingProperties(
                outputProperties.reduce(into: [String: Any]()) { $0[$1.key as String] = $1.value }
            )
            let hdrOptions: [CIImageRepresentationOption: Any] = [
                .hdrImage: measuredHDR,
                .hdrGainMapAsRGB: true,
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String):
                    max(0, min(1, options.compressionQuality))
            ]
            if format == .jpeg {
                try context.writeJPEGRepresentation(
                    of: base, to: temporaryURL, colorSpace: outputColorSpace, options: hdrOptions
                )
            } else {
                try context.writeHEIFRepresentation(
                    of: base, to: temporaryURL, format: .RGBA8, colorSpace: outputColorSpace,
                    options: hdrOptions
                )
            }
        } else {
            guard let destination = CGImageDestinationCreateWithURL(
                temporaryURL as CFURL, type.identifier as CFString, 1, nil
            ) else { throw ImageExporterError.destinationCreationFailed }
            CGImageDestinationAddImage(destination, cgImage, outputProperties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw ImageExporterError.finalizeFailed
            }
        }

        if destinationURL != nil, FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        }
        return outputURL
    }

    private func uniformType(for format: OutputFormat) throws -> UTType {
        switch format {
        case .jpeg: .jpeg
        case .heic: .heic
        case .png: .png
        case .tiff, .sameAsSource: .tiff
        }
    }

    private func sourceColorSpace(from source: CGImageSource?) -> CGColorSpace? {
        guard let source, let image = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceDecodeRequest: kCGImageSourceDecodeToSDR
        ] as CFDictionary), let colorSpace = image.colorSpace else { return nil }
        // PQ/HLG and extended spaces must not be assigned to the SDR base.
        return colorSpace.isHDR() || CGColorSpaceUsesExtendedRange(colorSpace)
            ? CGColorSpace(name: CGColorSpace.displayP3) : colorSpace
    }

    /// Scales the image down to the requested long edge, if one is set.
    private func resized(_ image: CIImage, for options: OutputOptions) -> CIImage {
        let extent = image.extent
        guard let target = options.resizedSize(for: extent.size),
              let filter = CIFilter(name: "CILanczosScaleTransform") else { return image }
        let scale = target.height / extent.height
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        // Scaling the width separately lands both sides on whole pixels.
        filter.setValue((target.width / extent.width) / scale, forKey: kCIInputAspectRatioKey)
        guard let output = filter.outputImage else { return image }
        return output.cropped(to: CGRect(origin: output.extent.origin, size: target))
    }
}
