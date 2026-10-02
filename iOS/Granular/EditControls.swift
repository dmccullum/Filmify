import GranularCore
import SwiftUI

// MARK: - Tools

/// One effect in the tool bar under the photo: its symbol and name, lit when
/// chosen and dimmed while the effect is off.
struct ToolTab: View {
    let effect: EditEffect
    let isSelected: Bool
    let isEnabled: Bool
    let isModified: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: effect.symbol)
                    .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                    .frame(height: 24)
                Text(effect.shortTitle)
                    .font(.caption2.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                // Marks a tool that's been changed from the recipe.
                Circle()
                    .frame(width: 4, height: 4)
                    .opacity(isModified ? 1 : 0)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: isSelected)
        .animation(.smooth(duration: 0.25), value: isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(effect.title)
        .accessibilityValue(isEnabled ? (isModified ? "On, edited" : "On") : "Off")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Sliders

/// One adjustment: its name and value over a slider. Double-tapping the name
/// puts back the recipe's own value.
struct ParameterSlider: View {
    let parameter: EffectParameter
    @Binding var value: Double
    /// The recipe's own value.
    let recipeValue: Double
    /// Called as a drag begins, before the first change.
    var onBegin: () -> Void = {}

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(parameter.title)
                Spacer()
                Text(parameter.display.text(for: value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: value))
                    .animation(.snappy(duration: 0.15), value: value)
            }
            .font(.subheadline)
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
        }
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
    let stock: FilmStockID
    let thumbnail: CGImage?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 5) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 2.5)
                        .opacity(isSelected ? 1 : 0)
                }
                .animation(.easeOut(duration: 0.2), value: thumbnail != nil)

                Text(stock.name)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: 64)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stock.name)
        .accessibilityHint(stock.vibe)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
