import SwiftUI

/// A developed frame, lifted off the film as a print over a blurred lightbox.
/// It grows out of the negative it was tapped from, and a flick sends it away.
struct FrameViewer: View {
    let url: URL
    /// The negative's thumbnail, so the print has something to show while the full image loads.
    let negative: CGImage?
    /// The negative's frame on screen.
    let origin: CGRect
    let onClose: () -> Void

    @State private var image: CGImage?
    @State private var isOpen = false
    @State private var drag: CGSize = .zero
    @State private var flung: CGSize?

    private static let border: CGFloat = 14
    private static let chin: CGFloat = 30

    var body: some View {
        GeometryReader { geometry in
            let bounds = geometry.frame(in: .global)
            let print = printSize(in: geometry.size)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.44)
            // The print starts as the negative: same spot, same width.
            let start = CGSize(
                width: origin.midX - bounds.minX - center.x,
                height: origin.midY - bounds.minY - center.y
            )
            let shrink = origin.width / max(print.width, 1)

            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.3))
                    .opacity(isOpen && flung == nil ? 1 - min(abs(drag.height) + abs(drag.width), 300) / 600 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }

                self.print(size: print)
                    .scaleEffect(isOpen ? 1 : shrink)
                    .rotationEffect(.degrees(isOpen ? Double(drag.width) / 18 - 1.5 : 0))
                    .offset(isOpen ? (flung ?? drag) : start)
                    .position(center)
                    .gesture(flick(in: geometry.size))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel("Developed photo")
                    .accessibilityAction(named: "Close") { close() }

                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(.horizontal, 40)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 12)
                .opacity(isOpen && flung == nil ? 1 : 0)
                .offset(y: isOpen ? 0 : 24)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            image = await Darkroom.thumbnail(of: url, maxPixelSize: 2_400)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.12)) { isOpen = true }
        }
    }

    private var aspect: CGFloat {
        let picture = image ?? negative
        guard let picture, picture.height > 0 else { return 4 / 5 }
        return CGFloat(picture.width) / CGFloat(picture.height)
    }

    /// The whole print, paper border included, fitted to the screen.
    private func printSize(in available: CGSize) -> CGSize {
        let maxWidth = available.width - 48
        let maxHeight = available.height * 0.62
        let extraWidth = Self.border * 2
        let extraHeight = Self.border + Self.chin
        let photoWidth = min(maxWidth - extraWidth, (maxHeight - extraHeight) * aspect)
        return CGSize(width: photoWidth + extraWidth, height: photoWidth / aspect + extraHeight)
    }

    private func print(size: CGSize) -> some View {
        let photo = CGSize(width: size.width - Self.border * 2, height: size.height - Self.border - Self.chin)
        return ZStack(alignment: .top) {
            Color(red: 0.97, green: 0.96, blue: 0.93)
                .opacity(isOpen ? 1 : 0)
            Group {
                if let picture = image ?? negative {
                    Image(decorative: picture, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.black.opacity(0.08)
                }
            }
            .frame(width: photo.width, height: photo.height)
            .clipped()
            .padding(.top, Self.border)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(isOpen ? 0.4 : 0), radius: 16, y: 10)
    }

    private func flick(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let predicted = value.predictedEndTranslation
                if hypot(predicted.width, predicted.height) > 420 {
                    // Carry on in the direction it was thrown.
                    let scale = max(size.width, size.height) * 1.4 / max(hypot(predicted.width, predicted.height), 1)
                    withAnimation(.easeOut(duration: 0.28)) {
                        flung = CGSize(width: predicted.width * scale, height: predicted.height * scale)
                    } completion: { onClose() }
                } else {
                    withAnimation(.spring(duration: 0.4, bounce: 0.25)) { drag = .zero }
                }
            }
    }

    /// The print settles back into its negative.
    private func close() {
        withAnimation(.spring(duration: 0.4, bounce: 0.05)) {
            drag = .zero
            isOpen = false
        } completion: { onClose() }
    }
}
