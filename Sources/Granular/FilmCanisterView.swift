import GranularCore
import SwiftUI

/// How a recipe's film is packaged: each built-in recipe gets its own canister,
/// saved recipes come in a design from the canister library, and unsaved edits
/// are bulk-loaded with a hand-written tape label.
enum CanisterStyle: Hashable {
    case classic
    case extra
    case clean
    case soft
    case printed(CanisterDesign, detail: String)
    case bulk(String)

    init(recipe: FilmRecipe, isModified: Bool) {
        if isModified {
            self = .bulk("Custom")
            return
        }
        switch recipe.id {
        case "classic-35": self = .classic
        case "extra-35": self = .extra
        case "clean-120": self = .clean
        case "soft-16": self = .soft
        default: self.init(design: CanisterDesign.resolved(for: recipe), recipe: recipe)
        }
    }

    init(design: CanisterDesign, recipe: FilmRecipe) {
        guard design.layout != .tape else {
            self = .bulk(recipe.name)
            return
        }
        // The small print names the stock the recipe is built on, if any.
        let stock = recipe.tone.isEnabled && recipe.tone.stock != .none ? recipe.tone.stock.name.uppercased() : nil
        self = .printed(design, detail: stock ?? "35 · 36 EXP")
    }

    /// Every recipe is loaded the same way; only the printing differs.
    var format: FilmFormat { .thirtyFive }
}

/// The canister's proportions on its 320 pt design grid, measured from a real
/// 35mm canister: thin caps, a tall label with the light-trap lip down one side,
/// and the spool button underneath (the way it sits in a camera).
enum CanisterGeometry {
    static let width: CGFloat = 154        // cap width; the body sits 2 pt inside
    static let bodyWidth: CGFloat = 150
    static let lipWidth: CGFloat = 20
    static let topCap: CGFloat = 17
    static let bodyHeight: CGFloat = 258
    static let bottomCap: CGFloat = 19
    static let buttonWidth: CGFloat = 68
    static let buttonHeight: CGFloat = 26
    static let height: CGFloat = 320
    /// Film is almost exactly as tall as the body it comes out of.
    static let filmToBody: CGFloat = 0.96
}

struct FilmFormat: Equatable {
    /// Top rebate band as a fraction of the strip height. The bottom band
    /// matches it plus room for the edge print, so the perforations sit the
    /// same distance from both edges of the film.
    var bandTop: CGFloat
    var perforatedTop: Bool
    var perforatedBottom: Bool
    var frameAspect: CGFloat
    var perforationsPerFrame: Int

    static let thirtyFive = FilmFormat(
        bandTop: 0.13,
        perforatedTop: true, perforatedBottom: true, frameAspect: 1.5, perforationsPerFrame: 8
    )
}

struct FilmCanisterView: View {
    let style: CanisterStyle
    let recipeName: String
    /// Rendered height; everything is laid out on a 320 pt design grid and scaled.
    let height: CGFloat
    /// Puts the light-trap lip down the left side, for a tin laid on its side
    /// with the film coming out of the top.
    var lipLeading = false
    var castsShadow = true

    private var s: CGFloat { height / CanisterGeometry.height }

    private let yellow = Color(hex: 0xF3B80C)
    private let cream = Color(hex: 0xEEE8DA)
    private let blue = Color(hex: 0x2B59A6)
    private let teal = Color(hex: 0x1D6B5A)
    private let paleTeal = Color(hex: 0xF2E7C9)

    var body: some View {
        Group {
            switch style {
            case .classic:
                tin(steelCaps: false) {
                    label(panel: yellow, panelText: FilmBackPalette.ink,
                          face: FilmBackPalette.ink, name: yellow, detail: Color(hex: 0xF2EDE4), detailText: "35 · 36 EXP")
                }
            case .extra:
                tin(steelCaps: false) {
                    label(panel: Color(hex: 0xDC4419), panelText: FilmBackPalette.ink,
                          face: FilmBackPalette.ink, name: Color(hex: 0xFFD21F), detail: Color(hex: 0xF2EDE4), detailText: "35 · 36 EXP",
                          hazard: true)
                }
            case .clean:
                tin(steelCaps: false) {
                    label(panel: blue, panelText: cream,
                          face: cream, name: blue, detail: FilmBackPalette.ink, detailText: "120 · FINE GRAIN")
                }
            case .soft:
                tin(steelCaps: true) {
                    label(panel: teal, panelText: paleTeal,
                          face: paleTeal, name: teal, detail: Color(hex: 0x3F5A52), detailText: "16 · SOFT GLOW")
                }
            case .printed(let design, let detail):
                tin(steelCaps: design.steelCaps) { printedLabel(design.layout, detail: detail) }
            case .bulk(let tape):
                tin(steelCaps: true) { bulkLabel(tape) }
            }
        }
        // Flatten the caps and body into one layer so no seams show when the
        // canister moves by fractional amounts.
        .drawingGroup()
        .shadow(color: .black.opacity(castsShadow ? 0.6 : 0), radius: 12 * s, y: 12 * s)
    }

    // MARK: Labels

    /// A vertical split, as on a real canister: a narrow coloured panel with small
    /// print, and a wider face carrying the name, reading bottom to top.
    private func label(
        panel: Color, panelText: Color,
        face: Color, name: Color, detail: Color, detailText: String,
        hazard: Bool = false, fullName: Bool = false
    ) -> some View {
        let word = fullName
            ? printedName
            : (recipeName.split(separator: " ").first.map(String.init) ?? recipeName).uppercased()
        let nameSize = fittedSize(word, length: 214, maximum: 36)
        return HStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                panel
                if hazard {
                    VStack {
                        HazardStripes().frame(height: 16 * s)
                        Spacer()
                    }
                }
                vertical("GRANULAR", size: 8.5, weight: .bold, color: panelText, tracking: 2.4)
                    .padding(.trailing, 5 * s)
                    .padding(.bottom, 16 * s)
            }
            .frame(width: 60 * s)

            ZStack(alignment: .bottom) {
                face
                HStack(alignment: .bottom, spacing: 3 * s) {
                    vertical(word, size: nameSize, weight: .semibold, color: name, tracking: 0.5)
                    vertical(detailText, size: 9, weight: .bold, color: detail, tracking: 1.6)
                        .padding(.bottom, 2 * s)
                }
                .padding(.bottom, 26 * s)
                chevron
                    .foregroundStyle(detail.opacity(0.8))
                    .padding(.bottom, 9 * s)
            }
        }
    }

    private func bulkLabel(_ tape: String) -> some View {
        ZStack {
            Color(hex: 0x1B1B1B)
            Text(tape)
                .font(.custom("Marker Felt", size: 22 * s).weight(.bold))
                .foregroundStyle(Color(hex: 0x1D1D1D))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.vertical, 14 * s)
                .padding(.horizontal, 10 * s)
                .frame(width: 124 * s)
                .background(
                    TapeShape().fill(
                        LinearGradient(colors: [Color(hex: 0xF0E7C8), Color(hex: 0xE0D2A6)], startPoint: .top, endPoint: .bottom)
                    )
                )
                .rotationEffect(.degrees(-6))
                .offset(y: -18 * s)
            VStack {
                Spacer()
                HStack(spacing: 5 * s) {
                    Text("BULK LOAD")
                        .font(.system(size: 11 * s, weight: .bold).width(.condensed))
                        .tracking(2.4 * s)
                    chevron
                }
                .foregroundStyle(Color(hex: 0x9AA0A4))
                .padding(.bottom, 12 * s)
            }
        }
    }

    // MARK: Library labels

    @ViewBuilder
    private func printedLabel(_ layout: CanisterDesign.Layout, detail: String) -> some View {
        switch layout {
        case let .split(panel, panelText, face, name, detailColor):
            label(panel: Color(hex: panel), panelText: Color(hex: panelText),
                  face: Color(hex: face), name: Color(hex: name), detail: Color(hex: detailColor),
                  detailText: detail, fullName: true)
        case let .bands(face, band, accent, name, detailColor):
            bandsLabel(face: Color(hex: face), band: Color(hex: band), accent: Color(hex: accent),
                       name: Color(hex: name), detail: Color(hex: detailColor), detailText: detail)
        case let .sash(face, stripe, edge, name, detailColor):
            sashLabel(face: Color(hex: face), stripe: Color(hex: stripe), edge: Color(hex: edge),
                      name: Color(hex: name), detail: Color(hex: detailColor), detailText: detail)
        case let .stripes(face, stripes, name, detailColor):
            stripesLabel(face: Color(hex: face), stripes: stripes.map { Color(hex: $0) },
                         name: Color(hex: name), detail: Color(hex: detailColor), detailText: detail)
        case let .paper(tin, paper, ink, rule):
            paperLabel(tin: Color(hex: tin), paper: Color(hex: paper), ink: Color(hex: ink),
                       rule: Color(hex: rule), detailText: detail)
        case .tape:
            bulkLabel(recipeName)
        }
    }

    /// A plain face between a heavy maker's band at the top and a thin one at
    /// the foot, with the name running up the middle.
    private func bandsLabel(face: Color, band: Color, accent: Color, name: Color, detail: Color, detailText: String) -> some View {
        VStack(spacing: 0) {
            ZStack {
                band
                Text("GRANULAR")
                    .font(.system(size: 10 * s, weight: .bold).width(.condensed))
                    .tracking(3 * s)
                    .foregroundStyle(face)
            }
            .frame(height: 38 * s)
            accent.frame(height: 5 * s).padding(.top, 4 * s)

            HStack(alignment: .bottom, spacing: 4 * s) {
                vertical(printedName, size: fittedSize(printedName, length: 150, maximum: 34),
                         weight: .semibold, color: name, tracking: 0.5)
                vertical(detailText, size: 9, weight: .bold, color: detail, tracking: 1.6)
                    .padding(.bottom, 2 * s)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 18 * s)
            .padding(.bottom, 10 * s)

            accent.frame(height: 2 * s).padding(.bottom, 3 * s)
            ZStack {
                band
                chevron.foregroundStyle(face.opacity(0.9))
            }
            .frame(height: 20 * s)
            .padding(.bottom, 12 * s)
        }
        .background(face)
    }

    /// A diagonal sash across the shoulder, dropping toward the lip, with the
    /// name running up from the foot beneath it.
    private func sashLabel(face: Color, stripe: Color, edge: Color, name: Color, detail: Color, detailText: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            face
            Canvas { context, size in
                let unit = size.height / CanisterGeometry.bodyHeight
                let rise = size.height * 0.30
                func sash(top: CGFloat, thickness: CGFloat) -> Path {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: top))
                    path.addLine(to: CGPoint(x: size.width, y: top + rise))
                    path.addLine(to: CGPoint(x: size.width, y: top + rise + thickness))
                    path.addLine(to: CGPoint(x: 0, y: top + thickness))
                    path.closeSubpath()
                    return path
                }
                context.fill(sash(top: 6 * unit, thickness: 4 * unit), with: .color(edge))
                context.fill(sash(top: 14 * unit, thickness: 40 * unit), with: .color(stripe))
                context.fill(sash(top: 58 * unit, thickness: 2 * unit), with: .color(edge))
            }
            HStack(alignment: .bottom, spacing: 3 * s) {
                vertical(printedName, size: fittedSize(printedName, length: 150, maximum: 34),
                         weight: .semibold, color: name, tracking: 0.5)
                vertical(detailText, size: 9, weight: .bold, color: detail, tracking: 1.6)
                    .padding(.bottom, 2 * s)
                Spacer(minLength: 0)
                vertical("GRANULAR", size: 8.5, weight: .bold, color: detail, tracking: 2.4)
                    .padding(.trailing, 6 * s)
            }
            .padding(.leading, 12 * s)
            .padding(.bottom, 26 * s)
            chevron
                .foregroundStyle(detail.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 9 * s)
        }
    }

    /// Thin stripes stacked across the shoulder, under the maker's name, with
    /// the recipe name running up from the foot.
    private func stripesLabel(face: Color, stripes: [Color], name: Color, detail: Color, detailText: String) -> some View {
        VStack(spacing: 0) {
            Text("GRANULAR")
                .font(.system(size: 10 * s, weight: .heavy).width(.condensed))
                .tracking(3 * s)
                .foregroundStyle(detail)
                .padding(.top, 14 * s)
                .padding(.bottom, 8 * s)
            VStack(spacing: 0) {
                ForEach(stripes.indices, id: \.self) { index in
                    stripes[index].frame(height: 9 * s)
                }
            }

            HStack(alignment: .bottom, spacing: 4 * s) {
                vertical(printedName, size: fittedSize(printedName, length: 140, maximum: 32),
                         weight: .semibold, color: name, tracking: 0.5)
                vertical(detailText, size: 9, weight: .bold, color: detail, tracking: 1.6)
                    .padding(.bottom, 2 * s)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 18 * s)
            .padding(.bottom, 26 * s)
            .overlay(alignment: .bottom) {
                chevron
                    .foregroundStyle(detail.opacity(0.8))
                    .padding(.bottom, 9 * s)
            }
        }
        .background(face)
    }

    /// A ruled paper label glued onto a bare tin, with the name typed up it.
    private func paperLabel(tin: Color, paper: Color, ink: Color, rule: Color, detailText: String) -> some View {
        let typewriter = "American Typewriter"
        return ZStack {
            tin
            VStack(spacing: 0) {
                Text("GRANULAR · 35MM")
                    .font(.custom(typewriter, size: 8.5 * s).weight(.semibold))
                    .tracking(1.2 * s)
                    .foregroundStyle(ink)
                    .padding(.top, 10 * s)
                rule.frame(height: 1.5 * s).padding(.horizontal, 8 * s).padding(.top, 5 * s)

                HStack(alignment: .bottom, spacing: 4 * s) {
                    vertical(printedName, size: fittedSize(printedName, length: 140, maximum: 26),
                             weight: .regular, color: ink, tracking: 0, fontName: typewriter)
                    vertical(detailText, size: 8.5, weight: .regular, color: ink.opacity(0.75), tracking: 1, fontName: typewriter)
                        .padding(.bottom, 2 * s)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 14 * s)
                .padding(.bottom, 10 * s)
                .background {
                    // Faint ruled lines, like a stock-room ledger card.
                    Canvas { context, size in
                        var y: CGFloat = 12 * s
                        while y < size.height {
                            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: max(0.5, 0.75 * s))),
                                         with: .color(ink.opacity(0.12)))
                            y += 14 * s
                        }
                    }
                }
            }
            .frame(width: 112 * s, height: 196 * s)
            .background(paper)
            .shadow(color: .black.opacity(0.35), radius: 1.5 * s, y: 1 * s)
            .rotationEffect(.degrees(-1.2))
            .offset(y: -6 * s)
        }
    }

    // MARK: Pieces

    /// A 35mm tin: thin caps, the printed label, the velvet light-trap lip down its
    /// right side, and the spool button underneath.
    private func tin<Printed: View>(steelCaps: Bool, @ViewBuilder label: () -> Printed) -> some View {
        let g = CanisterGeometry.self
        return VStack(spacing: 0) {
            cap(height: g.topCap, steel: steelCaps, top: true)
            HStack(spacing: 0) {
                if lipLeading {
                    lip.frame(width: g.lipWidth * s)
                }
                label()
                if !lipLeading {
                    lip.frame(width: g.lipWidth * s)
                }
            }
            .overlay(CylinderShade())
            .frame(width: g.bodyWidth * s, height: g.bodyHeight * s)
            .clipped()
            cap(height: g.bottomCap, steel: steelCaps, top: false)
            ZStack {
                (steelCaps ? Color(hex: 0xB4B9BD) : Color(hex: 0x111113))
                CylinderShade()
            }
            .frame(width: g.buttonWidth * s, height: g.buttonHeight * s)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 5 * s, bottomTrailingRadius: 5 * s))
        }
        .frame(width: g.width * s, height: g.height * s)
    }

    private var lip: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x0B0A0A)))
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color(hex: 0x1C1A19)))
                y += 3
            }
        }
    }

    /// Smooth, glossy caps, standing just proud of the body.
    private func cap(height: CGFloat, steel: Bool, top: Bool) -> some View {
        let big = 4 * s
        let small = 1.5 * s
        return ZStack {
            steel ? Color(hex: 0xC4C9CD) : Color(hex: 0x111113)
            CylinderShade()
            // A lit rim along the cap's outer edge.
            VStack {
                if !top { Spacer() }
                Color.white.opacity(steel ? 0.35 : 0.14).frame(height: 1.5 * s)
                if top { Spacer() }
            }
        }
        .frame(width: CanisterGeometry.width * s, height: height * s)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: top ? big : small,
                bottomLeadingRadius: top ? small : big,
                bottomTrailingRadius: top ? small : big,
                topTrailingRadius: top ? big : small
            )
        )
    }

    /// The whole recipe name for a tin that carries it, shortened if it would
    /// have to be printed too small to read.
    private var printedName: String {
        let name = recipeName.uppercased()
        return name.count > 24 ? String(name.prefix(23)) + "…" : name
    }

    /// The largest condensed type size at which the text fits the given length.
    private func fittedSize(_ text: String, length: CGFloat, maximum: CGFloat) -> CGFloat {
        min(maximum, length / (CGFloat(max(text.count, 3)) * 0.52))
    }

    private func vertical(
        _ text: String, size: CGFloat, weight: Font.Weight, color: Color, tracking: CGFloat,
        fontName: String? = nil
    ) -> some View {
        VerticalLabel {
            Text(text)
                .font(fontName.map { .custom($0, size: size * s).weight(weight) }
                      ?? .system(size: size * s, weight: weight).width(.condensed))
                .tracking(tracking * s)
                .foregroundStyle(color)
                .fixedSize()
                .rotationEffect(.degrees(-90))
        }
    }

    /// Left off icon-sized canisters, where symbols stop scaling down with the tin.
    @ViewBuilder
    private var chevron: some View {
        if height >= 60 {
            Image(systemName: "chevron.down")
                .font(.system(size: 9 * s, weight: .heavy))
        }
    }
}

private struct TapeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (0, 0.05), (0.04, 0), (0.30, 0.03), (0.62, 0), (0.96, 0.03), (1, 0),
            (0.98, 0.5), (1, 1), (0.70, 0.97), (0.35, 1), (0.03, 0.96), (0, 1), (0.02, 0.5)
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

