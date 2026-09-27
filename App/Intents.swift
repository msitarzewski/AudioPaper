import AppIntents
import AppKit
import AudioPaperKit

// Siri, Shortcuts and Spotlight (App Intents), run inside the app. What's on the desktop and where it came
// from, answered out loud; plus Next Image, Pause and Resume. The widget's buttons have their own intents in
// the widget extension, which signal the app instead.

/// "AudioPaper credit" — the credit of the image on the desktop, as a sentence.
struct DesktopImageIntent: AppIntent {
    static let title: LocalizedStringResource = "What's on My Desktop"
    static let description = IntentDescription("Says what AudioPaper has put on the desktop, who made it, and where it came from.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = AppModel.shared.coordinator.desktopDescription
        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }
}

/// Opens the page the image on the desktop came from, in the browser.
struct OpenImageSourceIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Where This Image Came From"
    static let description = IntentDescription("Opens the page the image on the desktop came from: the photo, the fan art, or the album.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let showing = AppModel.shared.coordinator.showing?.candidate, let page = showing.attribution.pageURL else {
            return .result(dialog: "There's no source page for what's on the desktop.")
        }
        NSWorkspace.shared.open(page)
        return .result(dialog: IntentDialog(stringLiteral: "Opening \(showing.attribution.sourceName)."))
    }
}

struct ShowNextImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Image"
    static let description = IntentDescription("Shows the next image in AudioPaper's rotation.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.coordinator.showNext()
        return .result()
    }
}

struct PauseWallpaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Wallpaper Changes"
    static let description = IntentDescription("Stops AudioPaper changing the wallpaper, leaving the current one up. The music keeps playing.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.coordinator.isSuspended = true
        return .result()
    }
}

struct ResumeWallpaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Wallpaper Changes"
    static let description = IntentDescription("Lets AudioPaper change the wallpaper with the music again.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.coordinator.isSuspended = false
        return .result()
    }
}

/// Phrases Siri knows without any setup. Apple requires the app's name in each one.
struct AudioPaperShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DesktopImageIntent(),
            // Commands, not questions: Siri answers questions like "what's on my desktop" itself (searching
            // the Desktop folder, or the web) instead of asking the app.
            phrases: [
                "\(.applicationName) credit",
                "Show \(.applicationName) credit",
                "Show the \(.applicationName) credit",
                "Read the \(.applicationName) credit",
            ],
            shortTitle: "What's on My Desktop",
            systemImageName: "info.circle"
        )
        AppShortcut(
            intent: OpenImageSourceIntent(),
            phrases: ["Open the \(.applicationName) image source", "Show me where my \(.applicationName) wallpaper came from"],
            shortTitle: "Open Image Source",
            systemImageName: "arrow.up.right.square"
        )
        AppShortcut(
            intent: ShowNextImageIntent(),
            phrases: ["Next image in \(.applicationName)", "Show the next \(.applicationName) image"],
            shortTitle: "Next Image",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: PauseWallpaperIntent(),
            phrases: ["Pause \(.applicationName)", "Pause wallpaper changes in \(.applicationName)"],
            shortTitle: "Pause Wallpaper Changes",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeWallpaperIntent(),
            phrases: ["Resume \(.applicationName)", "Resume wallpaper changes in \(.applicationName)"],
            shortTitle: "Resume Wallpaper Changes",
            systemImageName: "play.fill"
        )
    }
}
