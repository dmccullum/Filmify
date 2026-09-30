import AppKit
import SwiftUI

/// The images open in Edit mode, shown along the foot of the canvas once
/// there’s more than one. Click to show one; ← and → move along it while it
/// has focus, and Delete closes the one showing.
struct EditorFilmstrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(model.openImageURLs, id: \.self) { url in
                        FilmstripThumbnail(
                            url: url,
                            image: model.imageThumbnails[url],
                            isSelected: url == model.selectedSourceURL,
                            isFocused: isFocused
                        ) {
                            isFocused = true
                            if url != model.selectedSourceURL {
                                model.showImage(url)
                            }
                        }
                        .id(url)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selectedSourceURL, initial: true) { _, url in
                guard let url else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    proxy.scrollTo(url, anchor: .center)
                }
            }
        }
        .frame(height: 68)
        .background(.black.opacity(0.12))
        .overlay(alignment: .top) { Divider() }
        .focusable(interactions: .edit)
        .focused($isFocused)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .left: model.showPreviousImage()
            case .right: model.showNextImage()
            default: break
            }
        }
        .onDeleteCommand(perform: model.closeEditorImage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open Images")
    }
}

private struct FilmstripThumbnail: View {
    @Environment(AppModel.self) private var model

    let url: URL
    let image: NSImage?
    let isSelected: Bool
    let isFocused: Bool
    let select: () -> Void
    @State private var isHovering = false

    private let height: CGFloat = 46

    var body: some View {
        Button(action: select) {
            thumbnail
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
                .padding(2.5)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isFocused ? Color.accentColor : Color.secondary,
                                lineWidth: 2
                            )
                    }
                }
                .opacity(isSelected || isHovering ? 1 : 0.72)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if isHovering {
                Button {
                    model.closeImage(url)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.62))
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: -3, y: -3)
                .accessibilityLabel("Close \(url.lastPathComponent)")
                .help("Close image")
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Show in Finder") {
                model.reveal(url)
            }
            Divider()
            Button("Close") {
                model.closeImage(url)
            }
            Button("Close All") {
                model.closeAllImages()
            }
        }
        .help(url.lastPathComponent)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
        }
    }

    /// True to the image’s shape, within reason, so a panorama doesn’t take over the strip.
    private var width: CGFloat {
        guard let image, image.size.height > 0 else { return height * 1.5 }
        return min(max(height * image.size.width / image.size.height, height * 0.66), height * 2)
    }
}
