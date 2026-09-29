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

    /// Renders straight to a bitmap for display; encoding a preview to a file
    /// format and decoding it again costs several times the render itself.
    public func previewImage(for image: CIImage, maximumDimension: CGFloat = 1_600) throws -> CGImage {
        let scale = min(1, maximumDimension / max(image.extent.width, image.extent.height))
        let preview = scale < 1
            ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : image
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
        guard let cgImage = context.createCGImage(
            preview,
            from: preview.extent.integral,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            throw ImageExporterError.imageCreationFailed
        }
        return cgImage
    }

    public func export(
        image: CIImage,
        sourceURL: URL,
        destinationFolder: URL,
        destinationURL: URL? = nil,
        options: OutputOptions
    ) throws -> URL {
        let format = resolvedFormat(options.format, sourceURL: sourceURL)
        let type = try uniformType(for: format)
        let outputURL = destinationURL ?? collisionSafeURL(
            sourceURL: sourceURL,
            destinationFolder: destinationFolder,
            fileExtension: type.preferredFilenameExtension ?? "tiff"
        )
        let actualDestinationFolder = outputURL.deletingLastPathComponent()
        let temporaryURL = actualDestinationFolder
            .appendingPathComponent(".granular-\(UUID().uuidString)")
            .appendingPathExtension(type.preferredFilenameExtension ?? "tmp")

        let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil)
        let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) } as? [CFString: Any]
        let outputColorSpace = sourceColorSpace(from: source) ?? CGColorSpace(name: CGColorSpace.sRGB)!

        guard let cgImage = context.createCGImage(
            image,
            from: image.extent,
            format: .RGBA8,
            colorSpace: outputColorSpace
        ) else {
            throw ImageExporterError.imageCreationFailed
        }

        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageExporterError.destinationCreationFailed
        }

        var outputProperties = properties ?? [:]
        outputProperties[kCGImagePropertyOrientation] = 1
        outputProperties[kCGImagePropertyPixelWidth] = cgImage.width
        outputProperties[kCGImagePropertyPixelHeight] = cgImage.height
        if options.stripLocationMetadata {
            outputProperties.removeValue(forKey: kCGImagePropertyGPSDictionary)
        }
        if format == .jpeg || format == .heic {
            outputProperties[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, options.compressionQuality))
        }

        CGImageDestinationAddImage(destination, cgImage, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw ImageExporterError.finalizeFailed
        }

        if destinationURL != nil, FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        }
        return outputURL
    }

    private func resolvedFormat(_ format: OutputFormat, sourceURL: URL) -> OutputFormat {
        guard format == .sameAsSource else { return format }
        return switch sourceURL.pathExtension.lowercased() {
        case "jpg", "jpeg": OutputFormat.jpeg
        case "heic", "heif": OutputFormat.heic
        case "png": OutputFormat.png
        case "tif", "tiff": OutputFormat.tiff
        default: OutputFormat.tiff
        }
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
        guard let source, let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image.colorSpace
    }

    private func collisionSafeURL(
        sourceURL: URL,
        destinationFolder: URL,
        fileExtension: String
    ) -> URL {
        let base = sourceURL.deletingPathExtension().lastPathComponent + " — Granular"
        var candidate = destinationFolder.appendingPathComponent(base).appendingPathExtension(fileExtension)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = destinationFolder
                .appendingPathComponent("\(base) \(suffix)")
                .appendingPathExtension(fileExtension)
            suffix += 1
        }
        return candidate
    }
}
