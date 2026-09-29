import GranularCore
import SwiftUI

/// The Film Stock control: a full-width field that opens a grid of every
/// stock rendered on the current photograph.
struct FilmStockPickerButton: View {
    @Environment(AppModel.self) private var model
    @Binding var stock: FilmStockID
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(stock.name)
                    .lineLimit(1)
                if let family = stock.family {
                    Text(family.title)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 22)
            .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help(stock.vibe)
        .accessibilityLabel("Film Stock, \(stock.name)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            FilmStockGrid(stock: $stock, dismiss: { isPresented = false })
                .environment(model)
        }
    }
}

private struct FilmStockGrid: View {
    @Environment(AppModel.self) private var model
    @Binding var stock: FilmStockID
    let dismiss: () -> Void
    @FocusState private var isFocused: Bool

    private static let columnCount = 4
    private let columns = Array(
        repeating: GridItem(.fixed(FilmStockTile.width), spacing: 8, alignment: .top),
        count: columnCount
    )

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section(title: nil, stocks: [.none])
                    ForEach(FilmStockFamily.allCases, id: \.self) { family in
                        section(title: family.title, stocks: family.stocks)
                    }
                }
                .padding(14)
            }
            .frame(width: CGFloat(Self.columnCount) * (FilmStockTile.width + 8) + 20)
            .frame(maxHeight: 560)
            .onAppear { proxy.scrollTo(stock, anchor: .center) }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            isFocused = true
            model.refreshStockThumbnails()
        }
        .onChange(of: model.recipe.tone) { _, _ in model.refreshStockThumbnails() }
        .onChange(of: model.selectedSourceURL) { _, _ in model.refreshStockThumbnails() }
        .onKeyPress(.leftArrow) { move(by: -1) }
        .onKeyPress(.rightArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -Self.columnCount) }
        .onKeyPress(.downArrow) { move(by: Self.columnCount) }
        .onKeyPress(.return) {
            dismiss()
            return .handled
        }
    }

    private func section(title: String?, stocks: [FilmStockID]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(stocks, id: \.self) { candidate in
                    FilmStockTile(
                        stock: candidate,
                        thumbnail: model.stockThumbnails[candidate],
                        isSelected: candidate == stock
                    ) {
                        stock = candidate
                    }
                    .id(candidate)
                }
            }
        }
    }

    private func move(by offset: Int) -> KeyPress.Result {
        let order = [FilmStockID.none] + FilmStockFamily.allCases.flatMap(\.stocks)
        guard let index = order.firstIndex(of: stock) else { return .ignored }
        stock = order[max(0, min(order.count - 1, index + offset))]
        return .handled
    }
}

private struct FilmStockTile: View {
    static let width: CGFloat = 84

    let stock: FilmStockID
    let thumbnail: NSImage?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                ZStack {
                    Rectangle()
                        .fill(.quaternary)
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    }
                }
                .frame(width: Self.width, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }
                .animation(.easeOut(duration: 0.18), value: thumbnail != nil)

                Text(stock.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help(stock.vibe)
        .accessibilityLabel(stock.name)
        .accessibilityHint(stock.vibe)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
