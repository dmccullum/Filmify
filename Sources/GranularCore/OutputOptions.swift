import CoreGraphics
import Foundation

public enum OutputFormat: String, CaseIterable, Codable, Sendable {
    case sameAsSource
    case jpeg
    case heic
    case png
    case tiff

    public var displayName: String {
        switch self {
        case .sameAsSource: "Same as Source"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .png: "PNG"
        case .tiff: "TIFF"
        }
    }
}

/// The color space an exported file is tagged with.
public enum OutputColorSpace: String, CaseIterable, Codable, Sendable {
    case keepSource
    case sRGB
    case displayP3

    public var displayName: String {
        switch self {
        case .keepSource: "Keep Source"
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        }
    }

    /// The color space to convert to, or nil to keep the source image’s.
    public var cgColorSpace: CGColorSpace? {
        switch self {
        case .keepSource: nil
        case .sRGB: CGColorSpace(name: CGColorSpace.sRGB)
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)
        }
    }
}

public struct OutputOptions: Codable, Hashable, Sendable {
    public var format: OutputFormat
    public var compressionQuality: Double
    public var stripLocationMetadata: Bool
    /// How output files are named; see `OutputNaming`. Empty means the default.
    public var filenameTemplate: String
    /// The size, in pixels, images are scaled down to along their longer edge.
    /// Nil leaves them at full size. Images already smaller are never enlarged.
    public var resizeLongEdge: Int?
    public var colorSpace: OutputColorSpace

    public init(
        format: OutputFormat = .sameAsSource,
        compressionQuality: Double = 0.94,
        stripLocationMetadata: Bool = true,
        filenameTemplate: String = OutputNaming.defaultTemplate,
        resizeLongEdge: Int? = nil,
        colorSpace: OutputColorSpace = .keepSource
    ) {
        self.format = format
        self.compressionQuality = compressionQuality
        self.stripLocationMetadata = stripLocationMetadata
        self.filenameTemplate = filenameTemplate
        self.resizeLongEdge = resizeLongEdge
        self.colorSpace = colorSpace
    }

    // Options saved before naming, resizing and color space existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(OutputFormat.self, forKey: .format) ?? .sameAsSource
        compressionQuality = try container.decodeIfPresent(Double.self, forKey: .compressionQuality) ?? 0.94
        stripLocationMetadata = try container.decodeIfPresent(Bool.self, forKey: .stripLocationMetadata) ?? true
        filenameTemplate = try container.decodeIfPresent(String.self, forKey: .filenameTemplate)
            ?? OutputNaming.defaultTemplate
        resizeLongEdge = try container.decodeIfPresent(Int.self, forKey: .resizeLongEdge)
        colorSpace = try container.decodeIfPresent(OutputColorSpace.self, forKey: .colorSpace) ?? .keepSource
    }

    /// The pixel size an image of `size` is exported at, or nil if it keeps its size.
    public func resizedSize(for size: CGSize) -> CGSize? {
        guard let resizeLongEdge, resizeLongEdge > 0 else { return nil }
        let longEdge = max(size.width, size.height)
        guard longEdge > CGFloat(resizeLongEdge) else { return nil }
        let scale = CGFloat(resizeLongEdge) / longEdge
        return CGSize(
            width: max(1, (size.width * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )
    }
}
