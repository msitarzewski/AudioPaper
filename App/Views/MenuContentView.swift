import AudioPaperKit
import SwiftUI

/// The menu bar popover: what's on the desktop, who made it, and the slideshow controls.
struct MenuContentView: View {
    let coordinator: NowPlayingCoordinator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hero
            if let showing = coordinator.showing {
                AttributionRow(artwork: showing)
            }
            if !slides.isEmpty || coordinator.isSearchingFanArt {
                filmstrip
            }
            controls
        }
        .padding(14)
        .frame(width: 340)
    }

    private var slides: [Artwork] {
        (coordinator.albumArtwork.map { [$0] } ?? []) + coordinator.fanArt
    }

    private var hero: some View {
        ArtworkImage(artwork: coordinator.showing ?? coordinator.albumArtwork)
            .frame(height: 200)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.track?.title ?? "Nothing playing")
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                .padding(10)
            }
            .clipShape(.rect(cornerRadius: 16))
    }

    private var subtitle: String {
        guard let track = coordinator.track else { return coordinator.status }
        return [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    private var filmstrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(slides) { artwork in
                    Button {
                        coordinator.show(artwork)
                    } label: {
                        ArtworkImage(artwork: artwork, maxPixelSize: 160)
                            .frame(width: 56, height: 56)
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.accentColor, lineWidth: coordinator.showing == artwork ? 2 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(artwork.candidate.attribution.title ?? artwork.candidate.attribution.sourceName)
                }
                if coordinator.isSearchingFanArt {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 56, height: 56)
                        .help("Looking for fan art")
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var controls: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                Button {
                    coordinator.isSuspended.toggle()
                } label: {
                    Label(coordinator.isSuspended ? "Resume" : "Pause", systemImage: coordinator.isSuspended ? "play.fill" : "pause.fill")
                }
                .help(coordinator.isSuspended ? "Resume changing the wallpaper" : "Stop changing the wallpaper")

                Button {
                    coordinator.showNext()
                } label: {
                    Label("Next", systemImage: "forward.fill")
                }
                .disabled(coordinator.fanArt.isEmpty)
                .help("Show the next fan art")

                Button {
                    coordinator.restoreOriginalWallpaper()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .help("Put back your original wallpaper")

                Spacer()

                Button {
                    NSApp.activate()
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .help("Quit AudioPaper")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }
}

/// Credits the artwork on screen, linking to the artist's profile and the page it came from.
struct AttributionRow: View {
    let artwork: Artwork

    private var attribution: Attribution { artwork.candidate.attribution }

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: attribution.creatorAvatarURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: artwork.candidate.kind == .albumCover ? "opticaldisc" : "paintpalette")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)
            .clipShape(.circle)

            VStack(alignment: .leading, spacing: 1) {
                if artwork.candidate.kind == .fanArt, let creator = attribution.creatorName {
                    if let profile = attribution.creatorProfileURL {
                        Link("Art by \(creator)", destination: profile)
                            .font(.callout.weight(.medium))
                    } else {
                        Text("Art by \(creator)").font(.callout.weight(.medium))
                    }
                } else {
                    Text(attribution.title ?? "Artwork")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }
                Text(artwork.candidate.kind == .albumCover ? "Album cover · \(attribution.sourceName)" : "Fan art · \(attribution.sourceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let page = attribution.pageURL {
                Link(destination: page) {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Open where this art was found")
            }
        }
    }
}
