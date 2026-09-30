import CoreImage
import Foundation
import ImageIO
import Testing
@testable import GranularCore

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("GranularOutputTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func solidImage(width: Int, height: Int) -> CIImage {
    CIImage(color: .init(red: 0.62, green: 0.28, blue: 0.12, alpha: 1))
        .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
}

private func imageProperties(at url: URL) throws -> [CFString: Any] {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
}

// MARK: Options

@Test func outputOptionsDefaultToTheirOriginalBehavior() {
    let options = OutputOptions()

    #expect(options.filenameTemplate == "{name} — Granular")
    #expect(options.resizeLongEdge == nil)
    #expect(options.colorSpace == .keepSource)
}

@Test func outputOptionsRoundTripThroughJSON() throws {
    let options = OutputOptions(
        format: .heic,
        compressionQuality: 0.8,
        stripLocationMetadata: false,
        filenameTemplate: "{date}_{counter}",
        resizeLongEdge: 2_048,
        colorSpace: .displayP3
    )
    let decoded = try JSONDecoder().decode(OutputOptions.self, from: JSONEncoder().encode(options))

    #expect(decoded == options)
}

@Test func outputOptionsSavedBeforeTheNewSettingsStillDecode() throws {
    let legacy = Data(#"{"format":"jpeg","compressionQuality":0.7,"stripLocationMetadata":false}"#.utf8)
    let decoded = try JSONDecoder().decode(OutputOptions.self, from: legacy)

    #expect(decoded.format == .jpeg)
    #expect(decoded.compressionQuality == 0.7)
    #expect(decoded.stripLocationMetadata == false)
    #expect(decoded.filenameTemplate == OutputNaming.defaultTemplate)
    #expect(decoded.resizeLongEdge == nil)
    #expect(decoded.colorSpace == .keepSource)
}

// MARK: Resize

@Test func resizeScalesTheLongEdgeAndKeepsTheAspectRatio() {
    let options = OutputOptions(resizeLongEdge: 1_000)

    #expect(options.resizedSize(for: CGSize(width: 4_000, height: 3_000)) == CGSize(width: 1_000, height: 750))
    #expect(options.resizedSize(for: CGSize(width: 3_000, height: 4_000)) == CGSize(width: 750, height: 1_000))
    #expect(options.resizedSize(for: CGSize(width: 3_001, height: 2_000)) == CGSize(width: 1_000, height: 666))
}

@Test func resizeNeverEnlargesAndIsOffByDefault() {
    #expect(OutputOptions(resizeLongEdge: 1_000).resizedSize(for: CGSize(width: 800, height: 600)) == nil)
    #expect(OutputOptions(resizeLongEdge: 1_000).resizedSize(for: CGSize(width: 1_000, height: 10)) == nil)
    #expect(OutputOptions().resizedSize(for: CGSize(width: 8_000, height: 6_000)) == nil)
    #expect(OutputOptions(resizeLongEdge: 0).resizedSize(for: CGSize(width: 8_000, height: 6_000)) == nil)
}

@Test func resizeKeepsPanoramasAtLeastOnePixelTall() {
    let size = OutputOptions(resizeLongEdge: 100).resizedSize(for: CGSize(width: 10_000, height: 4))
    #expect(size == CGSize(width: 100, height: 1))
}

// MARK: Naming

private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

@Test func defaultTemplateKeepsTheOriginalNaming() {
    #expect(OutputNaming.render(template: OutputNaming.defaultTemplate, name: "IMG_1", recipe: "Classic 35")
        == "IMG_1 — Granular")
    #expect(OutputNaming.render(template: "", name: "IMG_1", recipe: "Classic 35") == "IMG_1 — Granular")
}

@Test func templateTokensExpandInPlace() {
    let name = OutputNaming.render(
        template: "{name}_{recipe}_{counter}",
        name: "IMG_1", recipe: "Soft 16", date: fixedDate, counter: 7
    )
    #expect(name == "IMG_1_Soft 16_007")

    let dated = OutputNaming.render(template: "{DATE} {Name}", name: "a", recipe: "", date: fixedDate)
    #expect(dated.hasSuffix(" a"))
    #expect(dated.range(of: #"^\d{4}-\d{2}-\d{2} a$"#, options: .regularExpression) != nil)
}

@Test func templateLeavesUnknownTokensAndUnbalancedBracesAlone() {
    #expect(OutputNaming.render(template: "{name} {size}", name: "a", recipe: "") == "a {size}")
    #expect(OutputNaming.render(template: "{name} {oops", name: "a", recipe: "") == "a {oops")
}

@Test func expandedValuesAreNotExpandedAgain() {
    #expect(OutputNaming.render(template: "{name}", name: "{recipe}", recipe: "Soft 16") == "{recipe}")
}

@Test func templateOutputIsAlwaysAUsableFileName() {
    #expect(OutputNaming.render(template: "{recipe}/{name}", name: "a", recipe: "b:c") == "b-c-a")
    #expect(OutputNaming.render(template: ".{name}", name: "a", recipe: "") == "a")
    // A template that comes to nothing falls back to the default.
    #expect(OutputNaming.render(template: "{recipe}", name: "a", recipe: "") == "a — Granular")
    #expect(OutputNaming.render(template: String(repeating: "x", count: 400), name: "a", recipe: "").count == 200)
}

@Test func uniqueURLAppendsANumberOnlyWhenTheNameIsTaken() {
    let folder = URL(fileURLWithPath: "/tmp/out", isDirectory: true)
    var taken: Set<String> = []
    func next(_ template: String) -> String {
        let url = OutputNaming.uniqueURL(
            template: template, name: "IMG_1", recipe: "R", date: fixedDate,
            folder: folder, fileExtension: "jpg", exists: { taken.contains($0.lastPathComponent) }
        )
        taken.insert(url.lastPathComponent)
        return url.lastPathComponent
    }

    #expect(next("{name} — Granular") == "IMG_1 — Granular.jpg")
    #expect(next("{name} — Granular") == "IMG_1 — Granular 2.jpg")
    #expect(next("{name} — Granular") == "IMG_1 — Granular 3.jpg")
}

@Test func counterTemplatesCountUpToTheFirstFreeName() {
    let folder = URL(fileURLWithPath: "/tmp/out", isDirectory: true)
    var taken: Set<String> = ["roll_001.png", "roll_002.png"]
    let url = OutputNaming.uniqueURL(
        template: "roll_{counter}", name: "IMG_1", recipe: "R",
        folder: folder, fileExtension: "png", exists: { taken.contains($0.lastPathComponent) }
    )
    #expect(url.lastPathComponent == "roll_003.png")
    taken.insert(url.lastPathComponent)
    #expect(OutputNaming.hasCounter("roll_{Counter}"))
    #expect(!OutputNaming.hasCounter("roll"))
}

// MARK: Export

@Test func exportAppliesTheFilenameTemplate() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = try ImageExporter().export(
        image: solidImage(width: 40, height: 30),
        sourceURL: directory.appendingPathComponent("frame.jpg"),
        destinationFolder: directory,
        recipeName: "Soft 16",
        options: .init(format: .png, filenameTemplate: "{name}-{recipe}-{counter}")
    )

    #expect(url.lastPathComponent == "frame-Soft 16-001.png")
}

@Test func exportScalesDownToTheLongEdge() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let exporter = ImageExporter()
    let url = try exporter.export(
        image: solidImage(width: 400, height: 300),
        sourceURL: directory.appendingPathComponent("frame.png"),
        destinationFolder: directory,
        options: .init(format: .png, resizeLongEdge: 100)
    )
    let properties = try imageProperties(at: url)
    #expect(properties[kCGImagePropertyPixelWidth] as? Int == 100)
    #expect(properties[kCGImagePropertyPixelHeight] as? Int == 75)

    let small = try exporter.export(
        image: solidImage(width: 60, height: 40),
        sourceURL: directory.appendingPathComponent("small.png"),
        destinationFolder: directory,
        options: .init(format: .png, resizeLongEdge: 100)
    )
    let smallProperties = try imageProperties(at: small)
    #expect(smallProperties[kCGImagePropertyPixelWidth] as? Int == 60)
    #expect(smallProperties[kCGImagePropertyPixelHeight] as? Int == 40)
}

@Test func exportTagsTheChosenColorSpace() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let exporter = ImageExporter()
    for (choice, expected) in [
        (OutputColorSpace.displayP3, "Display P3"),
        (OutputColorSpace.sRGB, "sRGB")
    ] {
        let url = try exporter.export(
            image: solidImage(width: 32, height: 32),
            sourceURL: directory.appendingPathComponent("\(choice.rawValue).png"),
            destinationFolder: directory,
            options: .init(format: .png, colorSpace: choice)
        )
        let profile = try imageProperties(at: url)[kCGImagePropertyProfileName] as? String
        #expect(profile?.contains(expected) == true)
    }
}

@Test func exportConvertsPixelsWhenTheColorSpaceChanges() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    // A saturated sRGB red is a less extreme red once described in Display P3,
    // so the pixels must change, not just the label.
    let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!)
        .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    func redChannel(_ space: OutputColorSpace) throws -> Int {
        let url = try ImageExporter().export(
            image: red,
            sourceURL: directory.appendingPathComponent("red-\(space.rawValue).png"),
            destinationFolder: directory,
            options: .init(format: .png, colorSpace: space)
        )
        let image = try #require(
            CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        )
        let fileSpace = try #require(image.colorSpace)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: fileSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Int(pixel[0])
    }

    // Read back in each file's own color space: only P3 has room to spare.
    let asSRGB = try redChannel(.sRGB)
    let asP3 = try redChannel(.displayP3)
    #expect(asSRGB >= 250)
    #expect(asP3 < 245)
}

// MARK: Window frames

@Test func windowFramePicksTheScreenItMostlyBelongsTo() {
    let left = CGRect(x: 0, y: 0, width: 1_440, height: 875)
    let right = CGRect(x: 1_440, y: 0, width: 1_920, height: 1_055)

    #expect(WindowFrameMath.bestVisibleFrame(for: CGRect(x: 1_200, y: 100, width: 600, height: 400), in: [left, right]) == right)
    #expect(WindowFrameMath.bestVisibleFrame(for: CGRect(x: 100, y: 100, width: 600, height: 400), in: [left, right]) == left)
}

@Test func windowFrameOnAScreenThatIsGoneHasNoHome() {
    let only = CGRect(x: 0, y: 0, width: 1_440, height: 875)

    #expect(WindowFrameMath.bestVisibleFrame(for: CGRect(x: 3_000, y: 100, width: 600, height: 400), in: [only]) == nil)
    // A sliver still on screen is not enough to grab.
    #expect(WindowFrameMath.bestVisibleFrame(for: CGRect(x: 1_400, y: 100, width: 600, height: 400), in: [only]) == nil)
}

@Test func clampingShrinksAndSlidesAFrameOnScreen() {
    let visible = CGRect(x: 0, y: 25, width: 1_440, height: 850)

    let oversized = WindowFrameMath.clamped(CGRect(x: -200, y: -100, width: 2_000, height: 1_200), to: visible)
    #expect(oversized == visible)

    let hanging = WindowFrameMath.clamped(CGRect(x: 1_300, y: 700, width: 600, height: 400), to: visible)
    #expect(hanging == CGRect(x: 840, y: 475, width: 600, height: 400))

    let inside = CGRect(x: 100, y: 100, width: 700, height: 400)
    #expect(WindowFrameMath.clamped(inside, to: visible) == inside)
}

@Test func clampingHonorsAMinimumSizeWhenTheScreenAllowsIt() {
    let visible = CGRect(x: 0, y: 0, width: 1_440, height: 800)
    let clamped = WindowFrameMath.clamped(
        CGRect(x: 0, y: 0, width: 300, height: 200), to: visible, minimumSize: CGSize(width: 620, height: 340)
    )
    #expect(clamped.size == CGSize(width: 620, height: 340))
}
