import GranularCore
import SwiftUI

// MARK: - Tools

/// One effect in the tool bar under the photo: yellow while it's the one
/// being adjusted, white while it's on, and faint while it's off.
struct ToolTab: View {
    static let width: CGFloat = 28

    let effect: EditEffect
    let isSelected: Bool
    let isEnabled: Bool
    let isModified: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: effect.symbol)
                    .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                    .frame(height: 26)
                // Marks a tool that's been changed from the recipe.
                Circle()
                    .frame(width: 4, height: 4)
                    .opacity(isModified ? 1 : 0)
            }
            .foregroundStyle(style)
            .frame(width: ToolTab.width, height: 44)
            // Reaches past the glyph, so the row is easy to hit end to end.
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .padding(.horizontal, -10)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: isSelected)
        .animation(.smooth(duration: 0.25), value: isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(effect.title)
        .accessibilityValue(isEnabled ? (isModified ? "On, edited" : "On") : "Off")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var style: Color {
        switch (isSelected, isEnabled) {
        case (true, true): .editSelection
        case (true, false): .editSelection.opacity(0.5)
        case (false, true): .white
        case (false, false): .white.opacity(0.3)
        }
    }
}

extension Color {
    /// The one color in Edit, as in Photos: the tool being adjusted.
    static let editSelection = Color(.systemYellow)
}

// MARK: - Sliders

/// One adjustment on a single line: its name, a slider and its value.
/// Double-tapping the name puts back the recipe's own value.
struct ParameterSlider: View {
    let parameter: EffectParameter
    @Binding var value: Double
    /// The recipe's own value.
    let recipeValue: Double
    /// Called as a drag begins, before the first change.
    var onBegin: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Text(parameter.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 80, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    withAnimation(.smooth) { value = recipeValue }
                }
                .accessibilityHidden(true)

            Slider(value: $value, in: parameter.range) { isEditing in
                if isEditing { onBegin() }
            }
            .accessibilityLabel(parameter.title)
            .accessibilityValue(parameter.display.accessibilityText(for: value))
            .accessibilityAction(named: "Reset to Recipe Value") { value = recipeValue }

            Text(parameter.display.text(for: value))
                .monospacedDigit()
                .foregroundStyle(value == recipeValue ? .secondary : .primary)
                .frame(width: 50, alignment: .trailing)
                .contentTransition(.numericText(value: value))
                .animation(.snappy(duration: 0.15), value: value)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
        .frame(height: 44)
        // A light tap as the slider passes the recipe's own value.
        .sensoryFeedback(trigger: value) { old, new in
            (old - recipeValue).sign != (new - recipeValue).sign || new == recipeValue ? .selection : nil
        }
    }
}

// MARK: - Film stocks

/// Every film stock as a thumbnail of the photo, in a strip that scrolls.
struct StockStrip: View {
    @Binding var stock: FilmStockID
    let thumbnails: [FilmStockID: CGImage]

    private static let order = [FilmStockID.none] + FilmStockFamily.allCases.flatMap(\.stocks)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Self.order, id: \.self) { candidate in
                        StockTile(
                            stock: candidate,
                            thumbnail: thumbnails[candidate],
                            isSelected: candidate == stock
                        ) {
                            stock = candidate
                        }
                        .id(candidate)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(stock, anchor: .center) }
            .onChange(of: stock) { _, stock in
                withAnimation(.smooth) { proxy.scrollTo(stock, anchor: .center) }
            }
        }
        .sensoryFeedback(.selection, trigger: stock)
    }
}

private struct StockTile: View {
    static let width: CGFloat = 52

    let stock: FilmStockID
    let thumbnail: CGImage?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 3) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
                .frame(width: StockTile.width, height: StockTile.width)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white, lineWidth: 2)
                        .opacity(isSelected ? 1 : 0)
                }
                .animation(.easeOut(duration: 0.2), value: thumbnail != nil)

                Text(stock.name)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: StockTile.width)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stock.name)
        .accessibilityHint(stock.vibe)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
