import AudioPaperKit
import SwiftUI

/// Displays a cached artwork file, decoded off the main thread at roughly the size it is drawn.
struct ArtworkImage: View {
    let artwork: Artwork?
    var maxPixelSize = 800

    @State private var image: NSImage?

    var body: some View {
        // The image is an overlay on a flexible shape, so a filled (cropped) image never widens the layout.
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: "music.note")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .task(id: artwork?.fileURL) {
                guard let file = artwork?.fileURL else {
                    image = nil
                    return
                }
                let size = maxPixelSize
                let decoded = await Task.detached(priority: .userInitiated) {
                    ImageLoading.image(at: file, maxPixelSize: size)
                }.value
                withAnimation(.easeInOut(duration: 0.35)) {
                    image = decoded.map { NSImage(cgImage: $0, size: .zero) }
                }
            }
    }
}
