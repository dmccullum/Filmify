import SwiftUI

/// A developed frame, printed full screen.
struct FrameViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Developed photo")
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            image = await Darkroom.thumbnail(of: url, maxPixelSize: 2_400)
        }
    }
}
