import GranularCore
import SwiftUI

/// How a recipe's film is packaged: each built-in recipe gets its own canister,
/// and saved or modified recipes are bulk-loaded with a hand-written tape label.
enum CanisterStyle: Hashable {
    case classic35
    case extra35
    case roll120
    case cine16
    case bulk(String)

    init(recipe: FilmRecipe, isModified: Bool) {
        if isModified {
            self = .bulk("Custom")
            return
        }
        switch recipe.id {
        case "classic-35": self = .classic35
        case "extra-35": self = .extra35
        case "clean-120": self = .roll120
        case "soft-16": self = .cine16
        default: self = .bulk(recipe.name)
        }
    }

    var format: FilmFormat {
        switch self {
        case .roll120: .oneTwenty
        case .cine16: .sixteen
        default: .thirtyFive
        }
    }

    /// Canister body width at the 320 pt design height.
    var designBodyWidth: CGFloat {
        switch self {
        case .roll120: 146
        case .cine16: 104
        default: 150
        }
    }
}

struct FilmFormat: Equatable {
    /// Strip height as a fraction of the film chamber height.
    var stripFraction: CGFloat
    /// Rebate bands as fractions of the strip height.
    var bandTop: CGFloat
    var bandBottom: CGFloat
    var perforatedTop: Bool
    var perforatedBottom: Bool
    var frameAspect: CGFloat
    var perforationsPerFrame: Int

    static let thirtyFive = FilmFormat(
        stripFraction: 0.66, bandTop: 0.13, bandBottom: 0.13,
        perforatedTop: true, perforatedBottom: true, frameAspect: 1.5, perforationsPerFrame: 8
    )
    static let oneTwenty = FilmFormat(
        stripFraction: 0.74, bandTop: 0.055, bandBottom: 0.055,
        perforatedTop: false, perforatedBottom: false, frameAspect: 1, perforationsPerFrame: 0
    )
    static let sixteen = FilmFormat(
        stripFraction: 0.56, bandTop: 0.07, bandBottom: 0.19,
        perforatedTop: false, perforatedBottom: true, frameAspect: 4 / 3, perforationsPerFrame: 2
    )
}

struct FilmCanisterView: View {
    let style: CanisterStyle
    let recipeName: String
    /// Rendered height; everything is laid out on a 320 pt design grid and scaled.
    let height: CGFloat

    private var s: CGFloat { height / 320 }

    private let yellow = Color(hex: 0xF3B80C)
    private let cream = Color(hex: 0xEEE8DA)
    private let blue = Color(hex: 0x2B59A6)
    private let teal = Color(hex: 0x1D6B5A)
    private let paleTeal = Color(hex: 0xF2E7C9)

    var body: some View {
        Group {
            switch style {
            case .classic35: classic
            case .extra35: extra
            case .roll120: roll
            case .cine16: cine
            case .bulk(let label): bulk(label)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.6), radius: 12 * s, y: 12 * s)
    }

    // MARK: Styles

    private var classic: some View {
        tin(bodyWidth: 150, steelCaps: false) {
            VStack(spacing: 0) {
                wordmark(color: yellow).frame(height: 22 * s).background(FilmBackPalette.ink)
                FilmBackPalette.signal.frame(height: 5 * s)
                nameColumn(nameColor: FilmBackPalette.ink, detail: "INSTANT · 36 EXP", detailColor: Color(hex: 0xB3340D))
                formatBlock("35", color: FilmBackPalette.ink).frame(height: 46 * s).background(FilmBackPalette.signal)
                FilmBackPalette.ink.frame(height: 8 * s)
            }
            .background(yellow)
        }
    }

    private var extra: some View {
        tin(bodyWidth: 150, steelCaps: false) {
            VStack(spacing: 0) {
                HazardStripes().frame(height: 20 * s)
                FilmBackPalette.ink.frame(height: 5 * s)
                nameColumn(nameColor: FilmBackPalette.ink, detail: "MORE GLOW · MORE GRAIN", detailColor: Color(hex: 0xFFE27A))
                formatBlock("35", color: Color(hex: 0xFFD21F)).frame(height: 46 * s).background(FilmBackPalette.ink)
                HazardStripes().frame(height: 8 * s)
            }
            .background(Color(hex: 0xDC4419))
        }
    }

    private var cine: some View {
        tin(bodyWidth: 104, steelCaps: true) {
            VStack(spacing: 0) {
                wordmark(color: teal, size: 9).frame(height: 20 * s).background(paleTeal)
                FilmBackPalette.signal.frame(height: 3 * s)
                nameColumn(nameColor: paleTeal, detail: "16MM CINE", detailColor: Color(hex: 0xBFE0D5))
                formatBlock("16", color: teal).frame(height: 42 * s).background(paleTeal)
                teal.frame(height: 6 * s)
            }
            .background(teal)
        }
    }

    private var roll: some View {
        VStack(spacing: 0) {
            smoothBlack.frame(width: 24 * s, height: 10 * s)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3 * s, topTrailingRadius: 3 * s))
            smoothBlack.frame(width: 158 * s, height: 12 * s).clipShape(RoundedRectangle(cornerRadius: 3 * s))
            ZStack {
                VStack(spacing: 0) {
                    wordmark(color: .white).frame(height: 36 * s).background(blue)
                    FilmBackPalette.ink.frame(height: 3 * s)
                    nameColumn(nameColor: blue, detail: "ROLL FILM · 12 EXP", detailColor: FilmBackPalette.ink)
                    formatBlock("120", color: cream).frame(height: 46 * s).background(FilmBackPalette.ink)
                    blue.frame(height: 14 * s)
                }
                .background(
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(cream))
                        var y: CGFloat = 0
                        while y < size.height {
                            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.6)), with: .color(.black.opacity(0.05)))
                            y += 5 * s
                        }
                    }
                )
                CylinderShade(strength: 0.85)
            }
            .frame(width: 146 * s, height: 272 * s)
            .clipped()
            smoothBlack.frame(width: 158 * s, height: 12 * s).clipShape(RoundedRectangle(cornerRadius: 3 * s))
        }
    }

    private func bulk(_ label: String) -> some View {
        tin(bodyWidth: 150, steelCaps: true) {
            ZStack {
                Color(hex: 0x1B1B1B)
                Text(label)
                    .font(.custom("Marker Felt", size: 24 * s).weight(.bold))
                    .foregroundStyle(Color(hex: 0x1D1D1D))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .padding(.vertical, 16 * s)
                    .padding(.horizontal, 12 * s)
                    .frame(width: 140 * s)
                    .background(
                        TapeShape().fill(
                            LinearGradient(colors: [Color(hex: 0xF0E7C8), Color(hex: 0xE0D2A6)], startPoint: .top, endPoint: .bottom)
                        )
                    )
                    .rotationEffect(.degrees(-6))
                    .offset(y: -22 * s)
                VStack {
                    Spacer()
                    HStack(spacing: 5 * s) {
                        Text("35 · BULK")
                            .font(.system(size: 12 * s, weight: .bold).width(.condensed))
                            .tracking(2.6 * s)
                        chevron
                    }
                    .foregroundStyle(Color(hex: 0x9AA0A4))
                    .padding(.bottom, 16 * s)
                }
            }
        }
    }

    // MARK: Pieces

    /// A metal 35mm-style tin: spool nub, caps, printed body and the velvet light-trap lip.
    private func tin<Printed: View>(
        bodyWidth: CGFloat,
        steelCaps: Bool,
        @ViewBuilder printed: () -> Printed
    ) -> some View {
        let bodyHeight: CGFloat = 266
        return VStack(spacing: 0) {
            cap(width: steelCaps ? bodyWidth * 0.2 : 34, height: 14, steel: steelCaps, top: true)
            cap(width: bodyWidth - 8, height: 20, steel: steelCaps, top: true)
            ZStack {
                printed()
                CylinderShade()
            }
            .frame(width: bodyWidth * s, height: bodyHeight * s)
            .clipped()
            cap(width: bodyWidth - 8, height: 20, steel: steelCaps, top: false)
        }
        .overlay(alignment: .topTrailing) {
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x090909)))
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color(hex: 0x1A1A1A)))
                    y += 3
                }
            }
                .frame(width: 10 * s, height: 256 * s)
                .clipShape(RoundedRectangle(cornerRadius: 2 * s))
                .offset(x: 6 * s, y: 39 * s)
        }
    }

    private func cap(width: CGFloat, height: CGFloat, steel: Bool, top: Bool) -> some View {
        let big = 6 * s
        let small = 2 * s
        return ZStack {
            if steel {
                Ribbed(dark: Color(hex: 0xAAB0B4), light: Color(hex: 0xDFE2E4), pitch: 4 * s)
            } else {
                Ribbed(dark: Color(hex: 0x0D0D0D), light: Color(hex: 0x2A2A2A), pitch: 5 * s)
            }
            CylinderShade()
        }
        .frame(width: width * s, height: height * s)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: top ? big : small,
                bottomLeadingRadius: top ? small : big,
                bottomTrailingRadius: top ? small : big,
                topTrailingRadius: top ? big : small
            )
        )
    }

    private var smoothBlack: some View {
        ZStack {
            Color(hex: 0x0A0A0A)
            CylinderShade(strength: 0.8)
        }
    }

    private func wordmark(color: Color, size: CGFloat = 10) -> some View {
        Text("GRANULAR")
            .font(.system(size: size * s, weight: .bold).width(.condensed))
            .tracking(3.4 * s)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
    }

    private func nameColumn(nameColor: Color, detail: String, detailColor: Color) -> some View {
        let word = (recipeName.split(separator: " ").first.map(String.init) ?? recipeName).uppercased()
        let nameSize = min(56, 150 / (CGFloat(max(word.count, 3)) * 0.46))
        return HStack(spacing: 4 * s) {
            VerticalLabel {
                Text(word)
                    .font(.system(size: nameSize * s, weight: .heavy).width(.condensed))
                    .italic()
                    .foregroundStyle(nameColor)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
            }
            VerticalLabel {
                Text(detail)
                    .font(.system(size: 9.5 * s, weight: .bold).width(.condensed))
                    .tracking(2.2 * s)
                    .foregroundStyle(detailColor)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatBlock(_ format: String, color: Color) -> some View {
        HStack(spacing: 5 * s) {
            Text(format).font(.system(size: 30 * s, weight: .heavy).width(.condensed))
            chevron
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 10 * s, weight: .heavy))
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
