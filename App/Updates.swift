import AppKit
import Sparkle

/// Sparkle auto-update. Sparkle asks on the second launch whether to check automatically (about once a
/// day); "Check for Updates…" checks now. Updates are verified against the EdDSA public key in Info.plist
/// before anything is installed.
@MainActor
final class Updates: NSObject {
    static let shared = Updates()

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self
    )

    /// Starts the updater (scheduled checks, if the person allowed them). Call once at launch.
    func start() {
        _ = controller
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

extension Updates: @preconcurrency SPUStandardUserDriverDelegate {
    /// AudioPaper lives in the menu bar, so a scheduled update shouldn't pop a window over whatever the
    /// person is doing: Sparkle shows it gently, and the app comes forward when it does.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
