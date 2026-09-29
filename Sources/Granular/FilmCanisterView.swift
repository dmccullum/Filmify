import GranularCore
import SwiftUI

/// How a recipe's film is packaged: each built-in recipe gets its own canister,
/// and saved or modified recipes are bulk-loaded with a hand-written tape label.
enum CanisterStyle: Hashable {
    case classic
    case extra
    case clean
    case soft
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
        default: self = .bulk(recipe.name)
        }
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
            case .bulk(let tape):
                tin(steelCaps: true) { bulkLabel(tape) }
            }
        }
        // Flatten the caps and body into one layer so no seams show when the
        // canister moves by fractional amounts.
        .drawingGroup()
        .shadow(color: .black.opacity(0.6), radius: 12 * s, y: 12 * s)
    }

    // MARK: Labels

    /// A vertical split, as on a real canister: a narrow coloured panel with small
    /// print, and a wider face carrying the name, reading bottom to top.
    private func label(
        panel: Color, panelText: Color,
        face: Color, name: Color, detail: Color, detailText: String,
        hazard: Bool = false
    ) -> some View {
        let word = (recipeName.split(separator: " ").first.map(String.init) ?? recipeName).uppercased()
        let nameSize = min(36, 214 / (CGFloat(max(word.count, 3)) * 0.52))
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

    // MARK: Pieces

    /// A 35mm tin: thin caps, the printed label, the velvet light-trap lip down its
    /// right side, and the spool button underneath.
    private func tin<Printed: View>(steelCaps: Bool, @ViewBuilder label: () -> Printed) -> some View {
        let g = CanisterGeometry.self
        return VStack(spacing: 0) {
            cap(height: g.topCap, steel: steelCaps, top: true)
            HStack(spacing: 0) {
                label()
                lip.frame(width: g.lipWidth * s)
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

    private func vertical(_ text: String, size: CGFloat, weight: Font.Weight, color: Color, tracking: CGFloat) -> some View {
        VerticalLabel {
            Text(text)
                .font(.system(size: size * s, weight: weight).width(.condensed))
                .tracking(tracking * s)
                .foregroundStyle(color)
                .fixedSize()
                .rotationEffect(.degrees(-90))
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9 * s, weight: .heavy))
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
