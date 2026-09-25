import AudioPaperKit
import SwiftUI

/// The Mini Player window: what's on the desktop, who made it, the slideshow, and its controls.
/// Modelled on Music's MiniPlayer — artwork-forward, draggable by its background, optionally floating.
struct MiniPlayerView: View {
    let coordinator: NowPlayingCoordinator
    @Bindable var preferences: Preferences
    @Environment(\.openSettings) private var openSettings
    /// Height of the hidden title bar. The artwork runs up under it, so the window gives it back at the
    /// bottom; otherwise the window sizes as if the title bar still took space, leaving a gap.
    @State private var titleBarHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Artwork runs to the window's top edge, under the traffic lights, as in Music's MiniPlayer.
            hero
            VStack(alignment: .leading, spacing: 12) {
                if let showing = coordinator.showing {
                    AttributionRow(artwork: showing)
                }
                if !coordinator.slides.isEmpty || coordinator.isSearchingFanArt {
                    filmstrip
                }
                controls
            }
            .padding(14)
        }
        .frame(width: 340)
        .padding(.bottom, -titleBarHeight)
        .ignoresSafeArea(edges: .top)
        // Liquid Glass: the desktop behind it is this same art, refracted through the system's glass.
        .background { GlassBackground().ignoresSafeArea() }
        .containerBackground(.clear, for: .window)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(WindowConfigurator(
            floats: preferences.miniPlayerFloatsOnTop,
            onAllDesktops: preferences.miniPlayerOnAllDesktops,
            titleBarHeight: $titleBarHeight
        ))
        .contextMenu { windowOptions }
    }

    private var hero: some View {
        ArtworkImage(artwork: coordinator.showing ?? coordinator.albumArtwork)
            .frame(height: 230)
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
            // Square top (the window's own corners round it); rounded where it meets the content below.
            .clipShape(.rect(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
            .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard let track = coordinator.track else { return coordinator.status }
        return [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(coordinator.slides) { artwork in
                        Button {
                            coordinator.show(artwork)
                        } label: {
                            ArtworkImage(artwork: artwork, maxPixelSize: 160)
                                .frame(width: 56, height: 56)
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.accentColor, lineWidth: coordinator.showing?.id == artwork.id ? 2 : 0)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(artwork.candidate.attribution.title ?? artwork.candidate.attribution.sourceName)
                        .accessibilityLabel(artwork.accessibilityName)
                        .accessibilityAddTraits(coordinator.showing?.id == artwork.id ? .isSelected : [])
                        .id(artwork.id)
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
            // Keep the image on the desktop in view, so its highlight is always visible.
            .onChange(of: coordinator.showing?.id, initial: true) { _, id in
                guard let id else { return }
                withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) }
            }
        }
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
                    Label("Next Image", systemImage: "forward.fill")
                }
                .disabled(coordinator.fanArt.isEmpty)
                .help("Show the next image")

                Button {
                    coordinator.restoreOriginalWallpaper()
                } label: {
                    Label("Restore Original Wallpaper", systemImage: "arrow.uturn.backward")
                }
                .help("Put back your original wallpaper")

                Spacer()

                // A real glass button (identical to its neighbours) that opens a native menu.
                Button {
                    showMoreMenu()
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .help("Window options and settings")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    /// Pops up the window options menu at the pointer (the "…" button's menu).
    private func showMoreMenu() {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Float on Top", checked: preferences.miniPlayerFloatsOnTop) {
            preferences.miniPlayerFloatsOnTop.toggle()
        })
        menu.addItem(ClosureMenuItem("Show on All Desktops", checked: preferences.miniPlayerOnAllDesktops) {
            preferences.miniPlayerOnAllDesktops.toggle()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…") {
            NSApp.activate()
            openSettings()
        })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @ViewBuilder
    private var windowOptions: some View {
        Toggle("Float on Top", isOn: $preferences.miniPlayerFloatsOnTop)
        Toggle("Show on All Desktops", isOn: $preferences.miniPlayerOnAllDesktops)
    }
}

/// The system's Liquid Glass material (`NSGlassEffectView`) as the window background.
private struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        // Matches the macOS 26 window corner so the glass fills the window shape exactly.
        view.cornerRadius = 16
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {}
}

/// Applies Mini Player window options SwiftUI doesn't expose: a remembered position, a transparent
/// window for the glass, floating level, joining all Spaces, and the hidden title bar's height.
private struct WindowConfigurator: NSViewRepresentable {
    let floats: Bool
    let onAllDesktops: Bool
    @Binding var titleBarHeight: CGFloat

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        // Runs now if the window exists, and again when the probe joins one.
        probe.configure = { window in apply(to: window) }
        if let window = probe.window { apply(to: window) }
    }

    private func apply(to window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.level = floats ? .floating : .normal
        if onAllDesktops {
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.collectionBehavior.remove(.moveToActiveSpace)
        } else {
            window.collectionBehavior.remove(.canJoinAllSpaces)
        }
        let height = window.frame.height - window.contentLayoutRect.height
        if height != titleBarHeight {
            // Not during the view update that called us.
            DispatchQueue.main.async { titleBarHeight = height }
        }
    }

    /// Reports the moment it's placed in a window, which `updateNSView` can't observe, and remembers the
    /// window's position between launches. (A frame autosave name doesn't survive SwiftUI placing the
    /// window after it, so the position is saved and restored explicitly.)
    final class Probe: NSView {
        static let positionKey = "miniPlayerTopLeft"
        var configure: ((NSWindow) -> Void)?
        private var moveObserver: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            configure?(window)
            restorePosition(of: window)
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: window, queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated {
                    guard let window else { return }
                    let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
                    UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: Self.positionKey)
                }
            }
        }

        /// Puts the window back where it was, once SwiftUI has finished placing it, unless that spot is no
        /// longer on any display.
        private func restorePosition(of window: NSWindow) {
            guard let saved = UserDefaults.standard.string(forKey: Self.positionKey) else { return }
            let topLeft = NSPointFromString(saved)
            guard NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(topLeft) }) else { return }
            DispatchQueue.main.async { window.setFrameTopLeftPoint(topLeft) }
        }
    }
}

extension Artwork {
    var accessibilityName: String {
        let attribution = candidate.attribution
        switch candidate.kind {
        case .albumCover: return "Album cover, \(attribution.title ?? "")"
        case .fanArt:
            let by = attribution.creatorName.map { " by \($0)" } ?? ""
            return "Fan art\(by), from \(attribution.sourceName)"
        }
    }
}

/// Credits the artwork on screen, linking to the artist's profile and the page it came from.
struct AttributionRow: View {
    let artwork: Artwork

    private var attribution: Attribution { artwork.candidate.attribution }

    var body: some View {
        HStack(spacing: 10) {
            AvatarImage(url: attribution.creatorAvatarURL, placeholder: artwork.candidate.kind == .albumCover ? "opticaldisc" : "paintpalette")
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

/// An artist's avatar, fetched through AudioPaper's cookie-free session. (`AsyncImage` uses the shared
/// system session, which stores cookies.)
private struct AvatarImage: View {
    let url: URL?
    let placeholder: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: placeholder).foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            image = nil
            guard let url, let (data, _) = try? await URLSessionHTTPClient().data(for: URLRequest(url: url)) else { return }
            image = NSImage(data: data)
        }
    }
}
