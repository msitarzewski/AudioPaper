import AppIntents
import AudioPaperKit
import SwiftUI
import WidgetKit

@main
struct AudioPaperWidgets: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        ArtworkWidget()
    }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Decoded thumbnails keyed by `WidgetSnapshot.Image.file`. Widget views can't load files lazily.
    let images: [String: NSImage]

    func image(_ item: WidgetSnapshot.Image?) -> NSImage? {
        item.flatMap { images[$0.file] }
    }

    /// The album cover: the first slide, when it is one.
    var cover: WidgetSnapshot.Image? {
        snapshot.slides.first { $0.kind == .albumCover }
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: .empty, images: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app reloads timelines whenever something changes; no polling needed.
        completion(Timeline(entries: [load()], policy: .never))
    }

    private func load() -> Entry {
        let snapshot = SharedStore.read()
        var images: [String: NSImage] = [:]
        for item in snapshot.slides + [snapshot.showing].compactMap({ $0 }) where images[item.file] == nil {
            if let cg = SharedStore.thumbnail(item) {
                images[item.file] = NSImage(cgImage: cg, size: .zero)
            }
        }
        return Entry(date: .now, snapshot: snapshot, images: images)
    }
}

// MARK: - Intents (run in the extension; they signal the app)

struct NextImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Image"
    static let description = IntentDescription("Shows the next fan art image as your wallpaper.")

    func perform() async throws -> some IntentResult {
        WidgetCommand.next.post()
        return .result()
    }
}

struct TogglePauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Wallpaper Changes"
    static let description = IntentDescription("Pauses or resumes AudioPaper changing your wallpaper.")

    func perform() async throws -> some IntentResult {
        WidgetCommand.togglePause.post()
        return .result()
    }
}

// MARK: - Now Playing

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NowPlaying", provider: Provider()) { entry in
            NowPlayingView(entry: entry)
                .widgetURL(WidgetLink.miniPlayer)
        }
        // The small size's artwork is its background; it must survive the system's background removal.
        .containerBackgroundRemovable(false)
        .configurationDisplayName("Now Playing")
        .description("The song that's playing and the art on your desktop, with slideshow controls.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NowPlayingView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemLarge: large
        default: medium
        }
    }

    private var track: Track? { entry.snapshot.track }

    /// Small: the cover fills the widget, with the song over a legibility scrim (like Music's widget).
    private var small: some View {
        VStack(alignment: .leading, spacing: 1) {
            Spacer()
            TrackText(track: track, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        .containerBackground(for: .widget) {
            // Covers often carry their own lettering; a stronger scrim keeps the song title readable over it.
            ArtworkFill(image: entry.image(entry.cover ?? entry.snapshot.showing))
                .overlay(alignment: .bottom) { Scrim(strength: .strong) }
        }
    }

    /// Medium: cover at left; song, credit and controls at right.
    private var medium: some View {
        HStack(spacing: 14) {
            ArtworkTile(image: entry.image(entry.cover ?? entry.snapshot.showing))
                .frame(maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 6) {
                TrackText(track: track, compact: false)
                Credit(item: entry.snapshot.showing)
                Spacer(minLength: 0)
                Controls(snapshot: entry.snapshot)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// Large: the image on the desktop, the song, the slideshow strip and controls.
    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArtworkTile(image: entry.image(entry.snapshot.showing ?? entry.cover))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    TrackText(track: track, compact: false)
                    Credit(item: entry.snapshot.showing)
                }
                Spacer(minLength: 8)
                Controls(snapshot: entry.snapshot)
            }
            if entry.snapshot.slides.count > 1 {
                HStack(spacing: 6) {
                    ForEach(entry.snapshot.slides.prefix(6)) { slide in
                        ArtworkTile(image: entry.image(slide), cornerRadius: 6)
                            .frame(width: 40, height: 40)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(.tint, lineWidth: slide.id == entry.snapshot.showing?.id ? 2 : 0)
                            }
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Artwork

struct ArtworkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Artwork", provider: Provider()) { entry in
            ArtworkWidgetView(entry: entry)
                .widgetURL(WidgetLink.miniPlayer)
        }
        .containerBackgroundRemovable(false)
        .configurationDisplayName("Artwork")
        .description("The image on your desktop right now, with credit to the artist who made it.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct ArtworkWidgetView: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
            if let showing = entry.snapshot.showing {
                Credit(item: showing)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            ArtworkFill(image: entry.image(entry.snapshot.showing ?? entry.cover))
                .overlay(alignment: .bottom) { Scrim() }
        }
    }
}

// MARK: - Pieces

struct TrackText: View {
    let track: Track?
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(track?.title ?? "Nothing Playing")
                .font(compact ? .headline : .title3.weight(.semibold))
                .lineLimit(compact ? 2 : 1)
            Text(track?.artist ?? "AudioPaper")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct Credit: View {
    let item: WidgetSnapshot.Image?

    var body: some View {
        if let item {
            Label {
                Text(line(for: item)).lineLimit(1)
            } icon: {
                Image(systemName: item.kind == .albumCover ? "opticaldisc" : "paintpalette")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func line(for item: WidgetSnapshot.Image) -> String {
        item.credit
    }
}

struct Controls: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: TogglePauseIntent()) {
                Label(snapshot.isSuspended ? "Resume" : "Pause", systemImage: snapshot.isSuspended ? "play.fill" : "pause.fill")
            }
            Button(intent: NextImageIntent()) {
                Label("Next Image", systemImage: "forward.fill")
            }
            .disabled(snapshot.slides.filter { $0.kind == .fanArt }.isEmpty)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }
}

struct ArtworkTile: View {
    let image: NSImage?
    var cornerRadius: CGFloat = 10

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .widgetAccentedRenderingMode(.desaturated)
                        .scaledToFill()
                } else {
                    Image(systemName: "music.note").font(.title2).foregroundStyle(.tertiary)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

struct ArtworkFill: View {
    let image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.desaturated)
                .scaledToFill()
        } else {
            Rectangle().fill(.fill.tertiary)
                .overlay { Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.tertiary) }
        }
    }
}

// Photos in widgets: when macOS draws desktop widgets in its accented (monochrome) style — the desktop
// isn't focused, or the person chose Monochrome — images are tinted like glyphs by default and turn into
// flat tiles. `.desaturated` keeps the artwork visible in grayscale, like Apple's Photos widget, without
// overriding the person's widget-style setting.

/// Bottom gradient that keeps white text legible over any artwork.
struct Scrim: View {
    enum Strength {
        /// A light fade for a single caption line.
        case regular
        /// Taller and darker, for a title and subtitle over busy art.
        case strong
    }

    var strength: Strength = .regular

    var body: some View {
        switch strength {
        case .regular:
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
        case .strong:
            LinearGradient(
                stops: [.init(color: .clear, location: 0.25), .init(color: .black.opacity(0.45), location: 0.55), .init(color: .black.opacity(0.8), location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}
